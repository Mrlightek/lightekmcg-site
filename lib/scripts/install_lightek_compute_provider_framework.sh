#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/compute_provider_framework_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in app/models/user.rb config/routes.rb config/initializers/lightek_dymond_dash_features.rb; do backup "$f"; done

mkdir -p app/models app/services/gatekeeper/compute/providers app/controllers/dashboard app/views/dashboard/compute_providers db/migrate lib/tasks
MIGRATION="db/migrate/${STAMP}_create_compute_providers.rb"

cat > "$MIGRATION" <<'RUBY'
class CreateComputeProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :compute_providers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :adapter_type, null: false, default: "declarative"
      t.string :adapter_class
      t.string :api_base_url
      t.string :documentation_url
      t.string :openapi_url
      t.string :credential_secret_slug
      t.string :status, null: false, default: "draft"
      t.string :health_status, null: false, default: "unknown"
      t.datetime :last_healthcheck_at
      t.jsonb :capabilities, null: false, default: {}
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :compute_providers, :slug, unique: true
    add_index :compute_providers, :status
    add_index :compute_providers, :health_status
    add_index :compute_providers, :capabilities, using: :gin
    add_index :compute_providers, :configuration, using: :gin
  end
end
RUBY

cat > app/models/compute_provider.rb <<'RUBY'
class ComputeProvider < ApplicationRecord
  ADAPTER_TYPES = %w[builtin declarative custom].freeze
  STATUSES = %w[draft validating active disabled].freeze
  HEALTH_STATUSES = %w[unknown healthy degraded failed].freeze

  validates :name, :slug, :adapter_type, :status, :health_status, presence: true
  validates :slug, uniqueness: true
  validates :adapter_type, inclusion: { in: ADAPTER_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :health_status, inclusion: { in: HEALTH_STATUSES }

  scope :active, -> { where(status: "active") }

  def adapter(requested_by: "system", operation_id: nil)
    Gatekeeper::Compute::Registry.build(self, requested_by:, operation_id:)
  end

  def capability?(name)
    capabilities.to_h[name.to_s] == true
  end

  def credential_configured?
    credential_secret_slug.present?
  end

  def mark_health!(status:, metadata: {})
    update!(
      health_status: status,
      last_healthcheck_at: Time.current,
      metadata: self.metadata.to_h.merge("last_healthcheck" => metadata)
    )
  end
end
RUBY

cat > app/services/gatekeeper/compute/provider.rb <<'RUBY'
module Gatekeeper
  module Compute
    class Provider
      class UnsupportedCapability < StandardError; end
      class ConfigurationError < StandardError; end

      attr_reader :provider, :requested_by, :operation_id

      def initialize(provider:, requested_by: "system", operation_id: nil)
        @provider = provider
        @requested_by = requested_by.to_s
        @operation_id = operation_id
      end

      def regions = unsupported!(:regions)
      def plans = unsupported!(:plans)
      def images = unsupported!(:images)
      def nodes = unsupported!(:nodes)
      def node(_id) = unsupported!(:node)
      def provision_node(**) = unsupported!(:provision_node)
      def reboot_node(_id) = unsupported!(:reboot_node)
      def shutdown_node(_id) = unsupported!(:shutdown_node)
      def start_node(_id) = unsupported!(:start_node)
      def destroy_node(_id) = unsupported!(:destroy_node)
      def set_reverse_dns(ip:, hostname:) = unsupported!(:set_reverse_dns)

      def healthcheck
        { ok: true, provider: provider.slug, adapter: self.class.name }
      end

      protected

      def vault_payload(purpose: "compute_management")
        slug = provider.credential_secret_slug
        raise ConfigurationError, "Provider has no Vault credential configured" if slug.blank?

        LightekVault::Service.checkout!(
          slug: slug,
          consumer: self.class.name,
          purpose: purpose,
          requested_by: requested_by,
          gatekeeper_operation_id: operation_id
        )
      end

      def unsupported!(capability)
        raise UnsupportedCapability, "#{provider.slug} does not implement #{capability}"
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/registry.rb <<'RUBY'
module Gatekeeper
  module Compute
    class Registry
      BUILTINS = {
        "linode" => "Gatekeeper::Compute::Providers::LinodeAdapter",
        "ovh" => "Gatekeeper::Compute::Providers::OvhAdapter"
      }.freeze

      def self.build(provider, requested_by: "system", operation_id: nil)
        klass_name =
          case provider.adapter_type
          when "builtin"
            provider.adapter_class.presence || BUILTINS.fetch(provider.slug)
          when "declarative"
            "Gatekeeper::Compute::Providers::DeclarativeAdapter"
          else
            provider.adapter_class.presence || raise(ArgumentError, "Custom provider requires adapter_class")
          end

        klass_name.constantize.new(provider:, requested_by:, operation_id:)
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/providers/http_support.rb <<'RUBY'
require "net/http"
require "json"
require "uri"
require "digest"

module Gatekeeper
  module Compute
    module Providers
      module HttpSupport
        private

        def json_request(method:, url:, headers: {}, body: nil)
          uri = URI(url)
          klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method.to_sym)
          req = klass.new(uri)
          req["Accept"] = "application/json"
          req["Content-Type"] = "application/json"
          req["User-Agent"] = "Lightek-Gatekeeper-Compute"
          headers.each { |k, v| req[k] = v }
          req.body = JSON.generate(body) if body

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 45) { |http| http.request(req) }
          parsed = res.body.to_s.blank? ? nil : JSON.parse(res.body)
          raise StandardError, "Provider HTTP #{res.code}: #{res.body.to_s.first(500)}" unless res.code.to_i.between?(200, 299)
          parsed
        rescue JSON::ParserError
          raise StandardError, "Provider returned invalid JSON"
        end
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/providers/linode_adapter.rb <<'RUBY'
module Gatekeeper
  module Compute
    module Providers
      class LinodeAdapter < Provider
        include HttpSupport
        BASE = "https://api.linode.com/v4".freeze

        def regions = collection("/regions")
        def plans = collection("/linode/types", authenticated: false)
        def images = collection("/images")
        def nodes = collection("/linode/instances")
        def node(id) = request(:get, "/linode/instances/#{id}")

        def provision_node(label:, region:, plan:, image:, root_password:, **options)
          request(:post, "/linode/instances", body: {
            label: label, region: region, type: plan, image: image, root_pass: root_password
          }.merge(options.compact))
        end

        def reboot_node(id) = request(:post, "/linode/instances/#{id}/reboot", body: {})
        def shutdown_node(id) = request(:post, "/linode/instances/#{id}/shutdown", body: {})
        def start_node(id) = request(:post, "/linode/instances/#{id}/boot", body: {})

        def destroy_node(id)
          request(:delete, "/linode/instances/#{id}")
          true
        end

        def set_reverse_dns(ip:, hostname:)
          request(:put, "/networking/ips/#{URI.encode_www_form_component(ip)}", body: { rdns: hostname })
        end

        def healthcheck
          data = request(:get, "/account")
          { ok: true, provider: provider.slug, account: data["company"].presence || data["email"].presence || "connected" }
        end

        private

        def token
          payload = vault_payload
          payload["token"] || payload["value"] || raise(ConfigurationError, "Linode Vault credential must contain token")
        end

        def request(method, path, body: nil, authenticated: true)
          headers = authenticated ? { "Authorization" => "Bearer #{token}" } : {}
          json_request(method:, url: "#{BASE}#{path}", headers:, body:)
        end

        def collection(path, authenticated: true)
          response = request(:get, path, authenticated: authenticated)
          response.is_a?(Hash) && response["data"].is_a?(Array) ? response["data"] : Array(response)
        end
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/providers/ovh_adapter.rb <<'RUBY'
module Gatekeeper
  module Compute
    module Providers
      class OvhAdapter < Provider
        include HttpSupport

        ENDPOINTS = {
          "ovh-eu" => "https://eu.api.ovh.com/1.0",
          "ovh-ca" => "https://ca.api.ovh.com/1.0",
          "ovh-us" => "https://api.us.ovhcloud.com/1.0"
        }.freeze

        def healthcheck
          data = ovh_request(:get, "/me")
          { ok: true, provider: provider.slug, account: data["nichandle"].presence || data["email"].presence || "connected" }
        end

        %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].each do |name|
          define_method(name) do |*args, **kwargs|
            mapped_call!(name, args:, kwargs:)
          end
        end

        private

        def credentials
          @credentials ||= begin
            payload = vault_payload
            creds = {
              application_key: payload["application_key"],
              application_secret: payload["application_secret"],
              consumer_key: payload["consumer_key"]
            }
            missing = creds.select { |_k, v| v.blank? }.keys
            raise ConfigurationError, "OVH Vault credential missing #{missing.join(', ')}" if missing.any?
            creds
          end
        end

        def base_url
          endpoint = provider.configuration.to_h["endpoint"].presence || "ovh-us"
          provider.api_base_url.presence || ENDPOINTS.fetch(endpoint)
        end

        def ovh_request(method, path, body: nil)
          creds = credentials
          body_json = body ? JSON.generate(body) : ""
          timestamp = Time.now.to_i
          url = "#{base_url}#{path}"
          material = [creds[:application_secret], creds[:consumer_key], method.to_s.upcase, url, body_json, timestamp].join("+")
          signature = "$1$#{Digest::SHA1.hexdigest(material)}"
          headers = {
            "X-Ovh-Application" => creds[:application_key],
            "X-Ovh-Consumer" => creds[:consumer_key],
            "X-Ovh-Timestamp" => timestamp.to_s,
            "X-Ovh-Signature" => signature
          }
          json_request(method:, url:, headers:, body:)
        end

        def mapped_call!(capability, args: [], kwargs: {})
          mapping = provider.configuration.to_h.dig("endpoints", capability)
          raise UnsupportedCapability, "OVH capability #{capability} has no endpoint mapping" unless mapping

          params = kwargs.stringify_keys
          args.each_with_index { |value, i| params["arg#{i + 1}"] = value }
          path = mapping.fetch("path").dup
          params.each { |key, value| path.gsub!("{#{key}}", URI.encode_www_form_component(value.to_s)) }
          service_name = provider.configuration.to_h["service_name"]
          path.gsub!("{service_name}", URI.encode_www_form_component(service_name.to_s)) if service_name.present?
          result = ovh_request(mapping.fetch("method", "GET").downcase.to_sym, path, body: mapping["send_body"] ? kwargs : mapping["body"])
          key = mapping["collection_key"]
          key.present? && result.is_a?(Hash) ? result.fetch(key, []) : result
        end
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/providers/declarative_adapter.rb <<'RUBY'
module Gatekeeper
  module Compute
    module Providers
      class DeclarativeAdapter < Provider
        include HttpSupport

        def healthcheck
          mapping = provider.configuration.to_h["healthcheck"]
          return super unless mapping
          invoke!(mapping)
          { ok: true, provider: provider.slug, adapter: self.class.name }
        end

        def regions = mapped!("regions")
        def plans = mapped!("plans")
        def images = mapped!("images")
        def nodes = mapped!("nodes")
        def node(id) = mapped!("node", id:)
        def provision_node(**kwargs) = mapped!("provision_node", **kwargs)
        def reboot_node(id) = mapped!("reboot_node", id:)
        def shutdown_node(id) = mapped!("shutdown_node", id:)
        def start_node(id) = mapped!("start_node", id:)
        def destroy_node(id) = mapped!("destroy_node", id:)
        def set_reverse_dns(ip:, hostname:) = mapped!("set_reverse_dns", ip:, hostname:)

        private

        def mapped!(name, **params)
          mapping = provider.configuration.to_h.dig("endpoints", name)
          raise UnsupportedCapability, "#{provider.slug} has no mapping for #{name}" unless mapping
          invoke!(mapping, params:)
        end

        def invoke!(mapping, params: {})
          path = mapping.fetch("path").dup
          params.stringify_keys.each { |k, v| path.gsub!("{#{k}}", URI.encode_www_form_component(v.to_s)) }
          credentials = provider.credential_secret_slug.present? ? vault_payload : {}
          headers = mapping.fetch("headers", {}).transform_values do |value|
            value.to_s.gsub(/\{\{credential\.([a-zA-Z0-9_]+)\}\}/) { credentials.fetch(Regexp.last_match(1)) }
          end
          result = json_request(
            method: mapping.fetch("method", "GET").downcase.to_sym,
            url: "#{provider.api_base_url.to_s.delete_suffix('/')}#{path}",
            headers:,
            body: mapping["send_body"] ? params : mapping["body"]
          )
          key = mapping["collection_key"]
          key.present? && result.is_a?(Hash) ? result.fetch(key, []) : result
        end
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/healthcheck_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class HealthcheckService
      def self.call(provider:, requested_by:)
        result = Registry.build(provider, requested_by:).healthcheck
        provider.mark_health!(status: result[:ok] ? "healthy" : "degraded", metadata: result.stringify_keys)
        result
      rescue StandardError => e
        provider.mark_health!(status: "failed", metadata: { "error_class" => e.class.name, "error_message" => e.message })
        raise
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/provider_onboarding_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ProviderOnboardingService
      DEFAULT_CAPABILITIES = %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(false).freeze

      def self.create!(attributes:, requested_by:)
        attrs = attributes.to_h.stringify_keys
        provider = ComputeProvider.create!(
          name: attrs.fetch("name"),
          slug: attrs.fetch("slug").parameterize(separator: "_"),
          adapter_type: attrs["adapter_type"].presence || "declarative",
          adapter_class: attrs["adapter_class"].presence,
          api_base_url: attrs["api_base_url"].presence,
          documentation_url: attrs["documentation_url"].presence,
          openapi_url: attrs["openapi_url"].presence,
          credential_secret_slug: attrs["credential_secret_slug"].presence,
          status: "draft",
          capabilities: DEFAULT_CAPABILITIES,
          configuration: {},
          metadata: { "created_by" => requested_by, "onboarding_state" => "needs_capability_mapping" }
        )
        record_kb_stub!(provider)
        provider
      end

      def self.record_kb_stub!(provider)
        return unless defined?(Gatekeeper::LessonService)
        Gatekeeper::LessonService.record!(
          key: "GK-PROVIDER-#{provider.slug.upcase}",
          title: "#{provider.name} compute provider onboarding",
          capability: "compute_provider_onboarding",
          symptom: "Lightek needs to manage infrastructure through #{provider.name}.",
          cause: "The provider is new to Gatekeeper and needs capability mappings, authentication policy, smoke tests, and operational procedures.",
          remediation: "Map the provider API to the Gatekeeper Compute Provider contract, store credentials in Lightek Vault, run read-only health checks, then perform approved billable/destructive smoke tests before activation.",
          verification: "Authentication passes; read-only capabilities pass; approved create/reboot/destroy smoke test passes; provider is marked active; all provider secret access is audited through Lightek Vault.",
          metadata: { provider_slug: provider.slug, documentation_url: provider.documentation_url, openapi_url: provider.openapi_url, onboarding_state: "needs_capability_mapping" }
        )
      rescue StandardError => e
        Rails.logger.warn "[ProviderOnboarding] KB stub failed: #{e.class}: #{e.message}"
      end
    end
  end
end
RUBY

cat > app/controllers/dashboard/compute_providers_controller.rb <<'RUBY'
class Dashboard::ComputeProvidersController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_provider, only: %i[show healthcheck activate disable]

  def index
    @providers = ComputeProvider.order(:name)
  end

  def show; end
  def new = (@provider = ComputeProvider.new(adapter_type: "declarative"))

  def create
    @provider = Gatekeeper::Compute::ProviderOnboardingService.create!(attributes: provider_params, requested_by: current_user.email_address)
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider added. Map capabilities and verify before activation."
  rescue StandardError => e
    @provider = ComputeProvider.new(provider_params)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def healthcheck
    result = Gatekeeper::Compute::HealthcheckService.call(provider: @provider, requested_by: current_user.email_address)
    redirect_to dashboard_compute_provider_path(@provider), notice: "Health check passed: #{result[:account] || result[:adapter] || 'connected'}."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(@provider), alert: "Health check failed: #{e.message}"
  end

  def activate
    @provider.update!(status: "active")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider activated."
  end

  def disable
    @provider.update!(status: "disabled")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider disabled."
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_provider = (@provider = ComputeProvider.find(params[:id]))

  def provider_params
    params.require(:compute_provider).permit(:name, :slug, :adapter_type, :adapter_class, :api_base_url, :documentation_url, :openapi_url, :credential_secret_slug)
  end
end
RUBY

cat > app/views/dashboard/compute_providers/index.html.erb <<'ERB'
<% content_for :page_title, "Compute Providers" %>
<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:20px">
  <div><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Gatekeeper · Compute Fabric</div><h2>Compute Providers</h2><p>Provider-neutral infrastructure control backed by Lightek Vault.</p></div>
  <%= link_to "Add Provider", new_dashboard_compute_provider_path, class:"dd-topbar-btn dd-btn-primary" %>
</div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px">
  <% @providers.each do |provider| %>
    <%= link_to dashboard_compute_provider_path(provider), style:"text-decoration:none;color:inherit" do %>
      <div class="dd-card" style="padding:18px"><div style="display:flex;justify-content:space-between"><strong><%= provider.name %></strong><span><%= provider.health_status.upcase %></span></div><div><%= provider.adapter_type %> · <%= provider.status %></div><div>Vault: <%= provider.credential_secret_slug.presence || "not configured" %></div></div>
    <% end %>
  <% end %>
</div>
ERB

cat > app/views/dashboard/compute_providers/new.html.erb <<'ERB'
<% content_for :page_title, "Add Compute Provider" %>
<div class="dd-card" style="padding:20px;max-width:760px">
  <h2>Add Compute Provider</h2>
  <p>Credentials must already exist in Lightek Vault.</p>
  <%= form_with model:@provider, url:dashboard_compute_providers_path do |f| %>
    <div style="display:grid;gap:12px">
      <%= f.text_field :name, placeholder:"Provider name", required:true %>
      <%= f.text_field :slug, placeholder:"Slug", required:true %>
      <%= f.select :adapter_type, ComputeProvider::ADAPTER_TYPES.map { |x| [x.humanize, x] } %>
      <%= f.text_field :adapter_class, placeholder:"Custom adapter class (custom only)" %>
      <%= f.url_field :api_base_url, placeholder:"API base URL" %>
      <%= f.url_field :documentation_url, placeholder:"Documentation URL" %>
      <%= f.url_field :openapi_url, placeholder:"OpenAPI URL" %>
      <%= f.text_field :credential_secret_slug, placeholder:"Vault secret slug" %>
      <%= f.submit "Add Provider", class:"dd-topbar-btn dd-btn-primary" %>
    </div>
  <% end %>
</div>
ERB

cat > app/views/dashboard/compute_providers/show.html.erb <<'ERB'
<% content_for :page_title, @provider.name %>
<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:20px">
  <div><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Compute Provider</div><h2><%= @provider.name %></h2><p><%= @provider.slug %> · <%= @provider.adapter_type %> · <%= @provider.status %></p></div>
  <%= button_to "Run Health Check", healthcheck_dashboard_compute_provider_path(@provider), method: :post, class:"dd-topbar-btn dd-btn-primary" %>
</div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px">
  <div class="dd-card" style="padding:18px"><h3>Connection</h3><p>Health: <strong><%= @provider.health_status %></strong></p><p>Last check: <%= @provider.last_healthcheck_at || "never" %></p><p>Vault: <code><%= @provider.credential_secret_slug.presence || "not configured" %></code></p></div>
  <div class="dd-card" style="padding:18px"><h3>Adapter</h3><p>Type: <%= @provider.adapter_type %></p><p>Class: <%= @provider.adapter_class.presence || "registry/default" %></p><p>API: <%= @provider.api_base_url.presence || "adapter default" %></p></div>
  <div class="dd-card" style="padding:18px"><h3>Onboarding</h3><p><%= @provider.metadata.to_h["onboarding_state"] || "configured" %></p><% if @provider.status != "active" %><%= button_to "Activate Provider", activate_dashboard_compute_provider_path(@provider), method: :post, class:"dd-topbar-btn dd-btn-primary" %><% else %><%= button_to "Disable Provider", disable_dashboard_compute_provider_path(@provider), method: :post, class:"dd-topbar-btn" %><% end %></div>
</div>
ERB

python3 <<'PY'
from pathlib import Path
p=Path('config/routes.rb'); s=p.read_text()
block='''resources :dashboard_compute_providers, path: "/dashboard/infrastructure/providers", controller: "dashboard/compute_providers", only: %i[index show new create] do
  member do
    post :healthcheck
    post :activate
    post :disable
  end
end

'''
if 'dashboard_compute_providers' not in s:
    marker='mount DymondDash::Engine => "/dashboard"'
    if marker not in s: raise SystemExit('ERROR: DymondDash mount not found')
    p.write_text(s.replace(marker, block+marker, 1))
PY

python3 <<'PY'
from pathlib import Path
p=Path('config/initializers/lightek_dymond_dash_features.rb'); s=p.read_text()
if 'compute_provider_management' not in s:
    anchor='rescue StandardError => e'
    if anchor not in s: raise SystemExit('ERROR: FeatureRegistry anchor not found')
    block='''  DymondDash::FeatureRegistry.register do |f|
    f.slug = :compute_provider_management
    f.label = "Compute Providers"
    f.icon = "server-cog"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Compute Providers", icon: "server-cog", path: "main_app.dashboard_compute_providers_path" }]
  end

'''
    p.write_text(s.replace(anchor, block+anchor, 1))
PY

cat > lib/tasks/compute_providers.rake <<'RUBY'
namespace :compute_providers do
  task seed: :environment do
    linode = ComputeProvider.find_or_initialize_by(slug: "linode")
    linode.assign_attributes(
      name: "Akamai / Linode", adapter_type: "builtin",
      adapter_class: "Gatekeeper::Compute::Providers::LinodeAdapter",
      api_base_url: "https://api.linode.com/v4",
      documentation_url: "https://techdocs.akamai.com/linode-api/reference/api",
      status: linode.status.presence || "draft",
      capabilities: %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(true),
      configuration: {}, metadata: linode.metadata.to_h.merge("builtin" => true)
    )
    linode.save!

    ovh = ComputeProvider.find_or_initialize_by(slug: "ovh")
    ovh.assign_attributes(
      name: "OVHcloud", adapter_type: "builtin",
      adapter_class: "Gatekeeper::Compute::Providers::OvhAdapter",
      documentation_url: "https://help.ovhcloud.com/",
      status: ovh.status.presence || "draft",
      capabilities: %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].index_with(false),
      configuration: { "endpoint" => "ovh-us", "endpoints" => {} },
      metadata: ovh.metadata.to_h.merge("builtin" => true, "note" => "Add service_name and endpoint mappings for the OVH product family Gatekeeper should manage.")
    )
    ovh.save!

    puts "Seeded #{linode.name} and #{ovh.name}"
  end

  task learn: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-COMPUTE-PROVIDER-CONTRACT",
      title: "Compute providers implement the Gatekeeper provider contract",
      capability: "compute_provider_onboarding",
      symptom: "Lightek needs to integrate a new infrastructure provider without coupling workflows to a vendor API.",
      cause: "Hard-coded provider calls leak vendor-specific logic into jobs, controllers, provisioning profiles, and customer workflows.",
      remediation: "Represent providers as ComputeProvider records. Store provider credentials only in Lightek Vault. Resolve builtin, declarative, or custom adapters through Gatekeeper::Compute::Registry. Validate read-only capabilities before any approved billable/destructive smoke test.",
      verification: "Provider is registered; Vault policy permits only its adapter; healthcheck passes; capability mappings are known; approved create/reboot/destroy test passes before activation.",
      metadata: { component: "gatekeeper_compute", adapter_types: %w[builtin declarative custom], credentials: "lightek_vault", auto_executable: false }
    )
    puts "Recorded GK-LESSON-COMPUTE-PROVIDER-CONTRACT as KB article #{article.id}"
  end
end
RUBY

echo '=== SYNTAX ==='
ruby -c "$MIGRATION"
for f in app/models/compute_provider.rb app/services/gatekeeper/compute/provider.rb app/services/gatekeeper/compute/registry.rb app/services/gatekeeper/compute/providers/http_support.rb app/services/gatekeeper/compute/providers/linode_adapter.rb app/services/gatekeeper/compute/providers/ovh_adapter.rb app/services/gatekeeper/compute/providers/declarative_adapter.rb app/services/gatekeeper/compute/healthcheck_service.rb app/services/gatekeeper/compute/provider_onboarding_service.rb app/controllers/dashboard/compute_providers_controller.rb config/routes.rb config/initializers/lightek_dymond_dash_features.rb lib/tasks/compute_providers.rake; do ruby -c "$f"; done

echo '=== MIGRATE ==='
bin/rails db:migrate

echo '=== ZEITWERK ==='
bin/rails zeitwerk:check

echo '=== SEED ==='
bin/rails compute_providers:seed

echo '=== ACCESS ==='
bin/rails runner '
sa=User.where(role:"super_admin").first; client=User.where(role:"client").first
puts "super_admin compute=#{sa&.can_access_feature?(:compute_provider_management).inspect}"
puts "client compute=#{client&.can_access_feature?(:compute_provider_management).inspect}"
puts "client susu=#{client&.can_access_feature?(:susu).inspect}"
'

echo '=== REGISTRY ==='
bin/rails runner 'ComputeProvider.order(:slug).each { |p| puts "#{p.slug}: #{Gatekeeper::Compute::Registry.build(p).class.name}" }'

echo '=== ROUTES ==='
bin/rails routes | grep dashboard_compute_provider

echo '=== FEATURE ==='
bin/rails runner 'f=DymondDash::FeatureRegistry.find(:compute_provider_management); abort "missing feature" unless f; puts "feature=#{f.slug} section=#{f.nav_section}"'

echo '=== KB ==='
bin/rails compute_providers:learn

echo '=== DIFF CHECK ==='
git diff --check

echo '=== STATUS ==='
git status --short

echo 'COMPUTE PROVIDER FRAMEWORK INSTALLED'
echo "Backup: $BACKUP"
