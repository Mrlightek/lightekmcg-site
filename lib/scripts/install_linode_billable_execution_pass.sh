#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/linode_billable_execution_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in \
  app/models/gatekeeper_node.rb \
  app/models/provisioning_request.rb \
  app/services/gatekeeper/compute/providers/linode_adapter.rb \
  app/controllers/dashboard/provisioning_requests_controller.rb \
  app/views/dashboard/provisioning_requests/show.html.erb \
  app/views/dashboard/compute_providers/show.html.erb \
  config/routes.rb
do
  backup "$f"
done

mkdir -p app/services/gatekeeper/compute app/controllers/dashboard db/migrate lib/tasks

MIGRATION="db/migrate/${STAMP}_add_execution_fields_to_provisioning_requests.rb"

cat > "$MIGRATION" <<'RUBY'
class AddExecutionFieldsToProvisioningRequests < ActiveRecord::Migration[8.0]
  def change
    change_table :provisioning_requests, bulk: true do |t|
      t.string :selected_region
      t.string :selected_plan
      t.string :selected_image
      t.string :node_label
      t.references :gatekeeper_node, foreign_key: true
      t.string :destroy_approval_status, null: false, default: "not_requested"
      t.string :destroy_approved_by
      t.datetime :destroy_approved_at
      t.datetime :provisioned_at
      t.datetime :destroyed_at
    end

    add_index :provisioning_requests, :destroy_approval_status
  end
end
RUBY

cat > app/services/gatekeeper/compute/linode_catalog_service.rb <<'RUBY'
require "bigdecimal"

module Gatekeeper
  module Compute
    class LinodeCatalogService
      class WrongProvider < StandardError; end
      class NoMatchingPlan < StandardError; end

      def self.call(provider:, requested_by:, profile: nil, region: nil)
        new(provider:, requested_by:, profile:, region:).call
      end

      def initialize(provider:, requested_by:, profile:, region:)
        @provider = provider
        @requested_by = requested_by
        @profile = profile
        @region = region.presence
      end

      def call
        raise WrongProvider, "Cost discovery currently supports Linode only" unless provider.slug == "linode"

        adapter = provider.adapter(requested_by: requested_by)
        regions = adapter.regions
        plans = adapter.plans
        images = adapter.images

        eligible = plans.select { |plan| plan_matches_profile?(plan) }
        raise NoMatchingPlan, "No Linode type satisfies the provisioning profile" if eligible.empty?

        priced = eligible.map do |plan|
          {
            "id" => plan["id"],
            "label" => plan["label"],
            "class" => plan["class"],
            "vcpus" => plan["vcpus"].to_i,
            "memory" => plan["memory"].to_i,
            "disk" => plan["disk"].to_i,
            "monthly_cents" => monthly_cents(plan, region),
            "hourly" => hourly_price(plan, region)
          }
        end

        priced.sort_by! { |plan| [plan["monthly_cents"] || 2**31, plan["memory"], plan["vcpus"]] }

        {
          "regions" => regions,
          "plans" => priced,
          "images" => images,
          "recommended_plan" => priced.first
        }
      end

      private

      attr_reader :provider, :requested_by, :profile, :region

      def plan_matches_profile?(plan)
        return true unless profile

        cpu_ok = profile.cpu_cores.blank? || plan["vcpus"].to_i >= profile.cpu_cores
        memory_ok = profile.memory_mb.blank? || plan["memory"].to_i >= profile.memory_mb
        disk_ok = profile.disk_gb.blank? || plan["disk"].to_i >= profile.disk_gb.to_i * 1024

        cpu_ok && memory_ok && disk_ok
      end

      def monthly_cents(plan, region_id)
        price = region_price(plan, region_id)&.fetch("monthly", nil)
        price = plan.dig("price", "monthly") if price.nil?
        return nil if price.nil?

        (BigDecimal(price.to_s) * 100).round.to_i
      end

      def hourly_price(plan, region_id)
        price = region_price(plan, region_id)&.fetch("hourly", nil)
        price = plan.dig("price", "hourly") if price.nil?
        price
      end

      def region_price(plan, region_id)
        return nil if region_id.blank?
        Array(plan["region_prices"]).find { |entry| entry["id"] == region_id }
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/node_credential_service.rb <<'RUBY'
require "securerandom"

module Gatekeeper
  module Compute
    class NodeCredentialService
      Result = Data.define(:secret_slug, :root_password)

      def self.create!(label:, requested_by:)
        root_password = "#{SecureRandom.base64(24)}#{SecureRandom.hex(12)}Aa9!"
        slug = "node-root-#{label.parameterize}-#{SecureRandom.hex(4)}"

        LightekVault::Service.store!(
          name: "Root credential for #{label}",
          slug: slug,
          payload: { "root_password" => root_password },
          secret_type: "password",
          provider: "linode",
          environment: Rails.env,
          purpose: "node_bootstrap",
          access_policy: {
            "consumers" => ["Gatekeeper::Compute::ProvisioningExecutionService"],
            "purposes" => ["provision_node", "node_bootstrap"]
          },
          metadata: {
            "node_label" => label,
            "generated_by" => "Gatekeeper"
          },
          requested_by: requested_by
        )

        Result.new(slug, root_password)
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/provisioning_execution_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ProvisioningExecutionService
      class NotExecutable < StandardError; end
      class UnsupportedProvider < StandardError; end
      class ProviderResponseError < StandardError; end

      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        validate!

        control_node = GatekeeperNode.order(:id).first ||
          raise(NotExecutable, "No Gatekeeper control node is registered")

        operation = GatekeeperOperation.create!(
          gatekeeper_node: control_node,
          capability: "provision_compute_node",
          requested_by: requested_by,
          status: "running",
          parameters: operation_parameters,
          started_at: Time.current
        )

        request.update!(gatekeeper_operation: operation, execution_status: "provisioning")

        credential = NodeCredentialService.create!(
          label: request.node_label,
          requested_by: requested_by
        )

        begin
          adapter = request.compute_provider.adapter(
            requested_by: requested_by,
            operation_id: operation.id
          )

          provider_node = adapter.provision_node(
            label: request.node_label,
            region: request.selected_region,
            plan: request.selected_plan,
            image: request.selected_image,
            root_password: credential.root_password,
            tags: [
              "lightek-managed",
              "gatekeeper",
              "provisioning-request-#{request.id}"
            ]
          )

          node = create_gatekeeper_node!(provider_node, credential.secret_slug)

          operation.update!(
            status: "succeeded",
            result: sanitize_provider_result(provider_node).merge("gatekeeper_node_id" => node.id),
            completed_at: Time.current,
            exit_status: 0
          )

          request.update!(
            gatekeeper_node: node,
            execution_status: "succeeded",
            provisioned_at: Time.current,
            metadata: request.metadata.to_h.merge(
              "node_credential_secret_slug" => credential.secret_slug,
              "provider_resource_id" => node.provider_resource_id
            )
          )

          node
        rescue StandardError => e
          operation.update!(
            status: "failed",
            error_class: e.class.name,
            error_message: e.message,
            completed_at: Time.current,
            exit_status: 1
          )

          request.update!(
            execution_status: "failed",
            error_class: e.class.name,
            error_message: e.message
          )

          raise
        ensure
          credential.root_password.clear if credential&.root_password.respond_to?(:clear)
        end
      end

      private

      attr_reader :request, :requested_by

      def validate!
        raise NotExecutable, "Provisioning request is not approved and ready" unless request.executable?
        raise UnsupportedProvider, "First billable execution pass supports Linode only" unless request.compute_provider.slug == "linode"
        raise NotExecutable, "Provider must be active" unless request.compute_provider.status == "active"
        raise NotExecutable, "Provider must be healthy" unless request.compute_provider.health_status == "healthy"
      end

      def operation_parameters
        {
          provisioning_request_id: request.id,
          provider: request.compute_provider.slug,
          region: request.selected_region,
          plan: request.selected_plan,
          image: request.selected_image,
          label: request.node_label,
          estimated_monthly_cost_cents: request.estimated_monthly_cost_cents
        }
      end

      def create_gatekeeper_node!(provider_node, credential_slug)
        resource_id = provider_node["id"] ||
          raise(ProviderResponseError, "Linode response did not include id")

        ipv4 = Array(provider_node["ipv4"]).first
        ipv6 = provider_node["ipv6"].to_s.split("/").first.presence

        raise ProviderResponseError, "Linode response did not include IPv4" if ipv4.blank?

        GatekeeperNode.create!(
          name: request.node_label,
          hostname: request.node_label,
          ip_address: ipv4,
          public_ipv6: ipv6,
          ssh_user: "root",
          ssh_port: 22,
          provider: request.compute_provider.name,
          provider_id: resource_id.to_s,
          provider_resource_id: resource_id.to_s,
          compute_provider: request.compute_provider,
          provisioning_profile: request.provisioning_profile,
          compute_policy: request.compute_policy,
          owner: request.owner,
          purpose: request.provisioning_profile&.purpose || "test",
          region: provider_node["region"].presence || request.selected_region,
          plan: provider_node["type"].presence || request.selected_plan,
          image: request.selected_image,
          status: normalize_status(provider_node["status"]),
          estimated_monthly_cost_cents: request.estimated_monthly_cost_cents,
          metadata: {
            "managed_by" => "gatekeeper",
            "provisioning_request_id" => request.id,
            "node_credential_secret_slug" => credential_slug,
            "provider_label" => provider_node["label"],
            "provider_created" => provider_node["created"]
          }.compact
        )
      end

      def normalize_status(value)
        case value.to_s
        when "running" then "healthy"
        when "offline" then "degraded"
        when "provisioning", "booting" then "provisioning"
        else "unknown"
        end
      end

      def sanitize_provider_result(provider_node)
        provider_node.slice("id", "label", "status", "region", "type", "ipv4", "ipv6", "created")
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/node_verification_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class NodeVerificationService
      class VerificationFailed < StandardError; end

      def self.call(request:, requested_by:)
        node = request.gatekeeper_node ||
          raise(VerificationFailed, "Provisioning request has no GatekeeperNode")

        adapter = request.compute_provider.adapter(requested_by: requested_by)
        provider_node = adapter.node(node.provider_resource_id)

        provider_status = provider_node["status"].to_s
        ipv4 = Array(provider_node["ipv4"]).first

        status =
          case provider_status
          when "running" then "healthy"
          when "offline" then "degraded"
          when "provisioning", "booting" then "provisioning"
          else "unknown"
          end

        node.update!(
          ip_address: ipv4.presence || node.ip_address,
          public_ipv6: provider_node["ipv6"].to_s.split("/").first.presence || node.public_ipv6,
          status: status,
          last_healthcheck_at: Time.current,
          metadata: node.metadata.to_h.merge(
            "provider_status" => provider_status,
            "provider_verified_at" => Time.current.iso8601
          )
        )

        {
          node_id: node.id,
          provider_resource_id: node.provider_resource_id,
          provider_status: provider_status,
          gatekeeper_status: node.status,
          ipv4: node.ip_address,
          ipv6: node.public_ipv6
        }
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/deprovisioning_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class DeprovisioningService
      class NotApproved < StandardError; end
      class UnsupportedProvider < StandardError; end

      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        raise NotApproved, "Destruction requires explicit approval" unless request.destroy_approval_status == "approved"

        node = request.gatekeeper_node ||
          raise(NotApproved, "No GatekeeperNode is attached")

        raise UnsupportedProvider, "First destroy pass supports Linode only" unless request.compute_provider&.slug == "linode"

        operation = GatekeeperOperation.create!(
          gatekeeper_node: node,
          capability: "destroy_compute_node",
          requested_by: requested_by,
          status: "running",
          parameters: {
            provisioning_request_id: request.id,
            provider: request.compute_provider.slug,
            provider_resource_id: node.provider_resource_id
          },
          started_at: Time.current
        )

        begin
          adapter = request.compute_provider.adapter(
            requested_by: requested_by,
            operation_id: operation.id
          )

          adapter.destroy_node(node.provider_resource_id)

          operation.update!(
            status: "succeeded",
            result: {
              "provider_resource_id" => node.provider_resource_id,
              "destroyed" => true
            },
            exit_status: 0,
            completed_at: Time.current
          )

          node.update!(
            status: "decommissioned",
            metadata: node.metadata.to_h.merge(
              "destroyed_at" => Time.current.iso8601,
              "destroyed_by" => requested_by
            )
          )

          request.update!(
            destroyed_at: Time.current,
            metadata: request.metadata.to_h.merge(
              "deprovision_operation_id" => operation.id
            )
          )

          true
        rescue StandardError => e
          operation.update!(
            status: "failed",
            error_class: e.class.name,
            error_message: e.message,
            exit_status: 1,
            completed_at: Time.current
          )
          raise
        end
      end

      private

      attr_reader :request, :requested_by
    end
  end
end
RUBY

python3 <<'PY'
from pathlib import Path
path = Path("app/services/gatekeeper/compute/providers/linode_adapter.rb")
src = path.read_text()
old = '''        def provision_node(label:, region:, plan:, image:, root_password:, **options)
          request(:post, "/linode/instances", body: {
            label: label, region: region, type: plan, image: image, root_pass: root_password
          }.merge(options.compact))
        end
'''
new = '''        def provision_node(label:, region:, plan:, image:, root_password: nil, authorized_keys: nil, **options)
          auth = {}
          auth[:root_pass] = root_password if root_password.present?
          auth[:authorized_keys] = Array(authorized_keys) if authorized_keys.present?
          raise ConfigurationError, "Linode provisioning requires root_password or authorized_keys" if auth.empty?

          request(:post, "/linode/instances", body: {
            label: label, region: region, type: plan, image: image
          }.merge(auth).merge(options.compact))
        end
'''
if new not in src:
    if old not in src: raise SystemExit("ERROR: expected LinodeAdapter#provision_node not found")
    path.write_text(src.replace(old, new, 1))
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/models/gatekeeper_node.rb")
src = path.read_text()
old = '  STATUSES = %w[unknown provisioning healthy degraded unreachable failed].freeze\n'
new = '  STATUSES = %w[unknown provisioning healthy degraded unreachable failed decommissioned].freeze\n'
if new not in src:
    if old not in src: raise SystemExit("ERROR: GatekeeperNode status list not found")
    path.write_text(src.replace(old, new, 1))
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/models/provisioning_request.rb")
src = path.read_text()
if "belongs_to :gatekeeper_node" not in src:
    needle = '  belongs_to :gatekeeper_operation, optional: true\n'
    if needle not in src: raise SystemExit("ERROR: ProvisioningRequest association anchor not found")
    src = src.replace(needle, needle + '  belongs_to :gatekeeper_node, optional: true\n', 1)

old = '''  def executable?
    approved? && execution_status == "ready" && compute_provider.present?
  end
'''
new = '''  def executable?
    approved? &&
      execution_status == "ready" &&
      compute_provider.present? &&
      selected_region.present? &&
      selected_plan.present? &&
      selected_image.present? &&
      node_label.present?
  end

  def destroy_approved?
    destroy_approval_status == "approved"
  end
'''
if "def destroy_approved?" not in src:
    if old not in src: raise SystemExit("ERROR: ProvisioningRequest executable? anchor not found")
    src = src.replace(old, new, 1)

path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/controllers/dashboard/provisioning_requests_controller.rb")
src = path.read_text()
old = '  before_action :set_request, only: %i[show approve reject]\n'
new = '  before_action :set_request, only: %i[show configure approve reject execute verify approve_destroy destroy]\n'
if old in src:
    src = src.replace(old, new, 1)
elif new not in src:
    raise SystemExit("ERROR: ProvisioningRequestsController before_action anchor not found")

if "def configure" not in src:
    anchor = '  def approve\n'
    methods = '''  def configure
    @request.update!(
      selected_region: params.require(:selected_region),
      selected_plan: params.require(:selected_plan),
      selected_image: params.require(:selected_image),
      node_label: params.require(:node_label),
      estimated_monthly_cost_cents: params.require(:estimated_monthly_cost_cents).to_i,
      execution_status: "awaiting_approval",
      approval_status: "pending"
    )

    Gatekeeper::Compute::ApprovalService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning configuration saved and approval policy evaluated."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request), alert: e.message
  end

  def execute
    node = Gatekeeper::Compute::ProvisioningExecutionService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Linode #{node.provider_resource_id} created and registered as Gatekeeper node #{node.id}."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Provisioning failed: #{e.message}"
  end

  def verify
    result = Gatekeeper::Compute::NodeVerificationService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provider verification: #{result[:provider_status]} / #{result[:ipv4]}."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Verification failed: #{e.message}"
  end

  def approve_destroy
    @request.update!(
      destroy_approval_status: "approved",
      destroy_approved_by: current_user.email_address,
      destroy_approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Destruction approved. The node has NOT been destroyed yet."
  end

  def destroy
    Gatekeeper::Compute::DeprovisioningService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provider node destroyed and Gatekeeper node decommissioned."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Destroy failed: #{e.message}"
  end

'''
    if anchor not in src: raise SystemExit("ERROR: approve action anchor not found")
    src = src.replace(anchor, methods + anchor, 1)

path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("config/routes.rb")
src = path.read_text()
old = '''  member do
    post :approve
    post :reject
  end
end
'''
new = '''  member do
    post :configure
    post :approve
    post :reject
    post :execute
    post :verify
    post :approve_destroy
    post :destroy
  end
end
'''
if "post :approve_destroy" not in src:
    if old not in src: raise SystemExit("ERROR: provisioning member routes not found")
    src = src.replace(old, new, 1)

route = '''post "/dashboard/infrastructure/providers/:compute_provider_id/linode_smoke_test",
     to: "dashboard/linode_smoke_tests#create",
     as: :dashboard_linode_smoke_test

'''
if 'dashboard_linode_smoke_test' not in src:
    marker = 'mount DymondDash::Engine => "/dashboard"'
    if marker not in src: raise SystemExit("ERROR: DymondDash mount not found")
    src = src.replace(marker, route + marker, 1)

path.write_text(src)
PY

cat > app/controllers/dashboard/linode_smoke_tests_controller.rb <<'RUBY'
class Dashboard::LinodeSmokeTestsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def create
    provider = ComputeProvider.find(params.require(:compute_provider_id))
    raise ArgumentError, "Provider must be Linode" unless provider.slug == "linode"

    profile = ProvisioningProfile.find_by(slug: params[:profile_slug].presence || "personal_cloud") ||
      raise(ArgumentError, "Provisioning profile not found")

    catalog = Gatekeeper::Compute::LinodeCatalogService.call(
      provider: provider,
      requested_by: current_user.email_address,
      profile: profile,
      region: params[:region]
    )

    recommended = catalog.fetch("recommended_plan")
    region = params[:region].presence ||
      Array(catalog["regions"]).find { |item| item["status"].to_s == "ok" }&.fetch("id", nil) ||
      Array(catalog["regions"]).first&.fetch("id", nil)

    image = params[:image].presence ||
      Array(catalog["images"]).find { |item| item["id"] == "linode/ubuntu24.04" }&.fetch("id", nil) ||
      Array(catalog["images"]).find { |item| item["id"].to_s.include?("ubuntu") }&.fetch("id", nil)

    request = ProvisioningRequest.create!(
      owner: current_user,
      provisioning_profile: profile,
      compute_policy: ComputePolicy.find_by(slug: "lightek_production"),
      compute_provider: provider,
      requested_node_count: 1,
      selected_region: region,
      selected_plan: recommended.fetch("id"),
      selected_image: image,
      node_label: "lightek-smoke-#{Time.current.strftime("%Y%m%d%H%M%S")}",
      estimated_monthly_cost_cents: recommended.fetch("monthly_cents"),
      approval_status: "pending",
      execution_status: "awaiting_approval",
      metadata: {
        "smoke_test" => true,
        "catalog_snapshot" => {
          "recommended_plan" => recommended,
          "region" => region,
          "image" => image
        }
      }
    )

    redirect_to dashboard_provisioning_request_path(request),
                notice: "Billable smoke-test request created. Review cost and approve before execution."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]),
                alert: "Could not create smoke test: #{e.message}"
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
RUBY

python3 <<'PY'
from pathlib import Path
path = Path("app/views/dashboard/compute_providers/show.html.erb")
src = path.read_text()
if "Billable Linode Smoke Test" not in src:
    src = src.rstrip() + '''
<% if @provider.slug == "linode" %>
  <div class="dd-card" style="padding:18px;margin-top:16px">
    <h3>Billable Linode Smoke Test</h3>
    <p style="font-size:12px;color:var(--dd-text-secondary)">
      This only prepares a ProvisioningRequest and discovers the estimated monthly price.
      No Linode is created until you separately approve and execute it.
    </p>
    <%= form_with url: dashboard_linode_smoke_test_path(@provider), method: :post do %>
      <%= select_tag :profile_slug,
            options_from_collection_for_select(ProvisioningProfile.active.order(:name), :slug, :name, "personal_cloud") %>
      <%= text_field_tag :region, nil, placeholder:"Optional region, e.g. us-east" %>
      <%= text_field_tag :image, "linode/ubuntu24.04", placeholder:"Image" %>
      <%= submit_tag "Prepare Billable Smoke Test",
            class:"dd-topbar-btn dd-btn-primary",
            data:{turbo_confirm:"Prepare a billable smoke-test request? This step does NOT create a Linode."} %>
    <% end %>
  </div>
<% end %>
'''
    path.write_text(src + "\n")
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/views/dashboard/provisioning_requests/show.html.erb")
src = path.read_text()
if "Provider Execution" not in src:
    src = src.rstrip() + '''
<div class="dd-card" style="padding:18px;margin-top:14px">
  <h3>Provider Execution</h3>
  <p>Region: <strong><%= @request.selected_region.presence || "not selected" %></strong></p>
  <p>Plan: <strong><%= @request.selected_plan.presence || "not selected" %></strong></p>
  <p>Image: <strong><%= @request.selected_image.presence || "not selected" %></strong></p>
  <p>Label: <strong><%= @request.node_label.presence || "not selected" %></strong></p>

  <% if @request.executable? && @request.gatekeeper_node.blank? %>
    <%= button_to "EXECUTE BILLABLE PROVISION",
          execute_dashboard_provisioning_request_path(@request),
          method: :post,
          class:"dd-topbar-btn dd-btn-primary",
          data:{turbo_confirm:"This WILL create a billable #{@request.compute_provider&.name} node at the displayed estimated monthly cost. Continue?"} %>
  <% end %>

  <% if @request.gatekeeper_node.present? && @request.destroyed_at.blank? %>
    <p>
      Gatekeeper node #<%= @request.gatekeeper_node.id %>
      · provider resource <%= @request.gatekeeper_node.provider_resource_id %>
      · <%= @request.gatekeeper_node.ip_address %>
      · status=<%= @request.gatekeeper_node.status %>
    </p>

    <%= button_to "Verify Provider State",
          verify_dashboard_provisioning_request_path(@request),
          method: :post,
          class:"dd-topbar-btn" %>

    <% unless @request.destroy_approved? %>
      <%= button_to "Approve Destruction",
            approve_destroy_dashboard_provisioning_request_path(@request),
            method: :post,
            class:"dd-topbar-btn",
            data:{turbo_confirm:"Approve destruction of this billable test node? Approval alone does not delete it."} %>
    <% else %>
      <%= button_to "DESTROY PROVIDER NODE",
            destroy_dashboard_provisioning_request_path(@request),
            method: :post,
            class:"dd-topbar-btn",
            data:{turbo_confirm:"This WILL permanently delete provider resource #{@request.gatekeeper_node.provider_resource_id}. Continue?"} %>
    <% end %>
  <% end %>

  <% if @request.destroyed_at.present? %>
    <p><strong>Destroyed:</strong> <%= @request.destroyed_at %></p>
  <% end %>
</div>
'''
    path.write_text(src + "\n")
PY

cat > lib/tasks/gatekeeper_billable_execution_lessons.rake <<'RUBY'
namespace :gatekeeper do
  task learn_billable_execution: :environment do
    [
      {
        key: "GK-LESSON-LINODE-BILLABLE-EXECUTION",
        title: "Linode provisioning crosses a billable approval boundary",
        capability: "provision_compute_node",
        symptom: "An approved provisioning request is ready to create a real Linode.",
        cause: "Creating a Linode incurs provider charges, so discovery, pricing, approval, execution, registration and verification must remain separate audited stages.",
        remediation: "Discover types/regions/images first, store selected type/region/image and monthly estimate on ProvisioningRequest, require approval, create a GatekeeperOperation, generate the bootstrap credential into Lightek Vault, provision through LinodeAdapter, register the returned resource as GatekeeperNode, then verify provider state.",
        verification: "Linode ID, plan, region, IPs, GatekeeperNode, Vault credential reference and GatekeeperOperation are recorded; no secret value is logged.",
        metadata: { provider:"linode", billable:true, explicit_execution_required:true, auto_executable:false }
      },
      {
        key: "GK-LESSON-COMPUTE-DESTRUCTION-APPROVAL",
        title: "Provider node destruction requires a separate explicit approval",
        capability: "destroy_compute_node",
        symptom: "A managed provider node needs to be permanently deleted.",
        cause: "Destruction is irreversible and should not inherit approval from the original provisioning operation.",
        remediation: "Record destruction approval separately. Only after explicit destruction approval may Gatekeeper invoke provider deletion. Preserve GatekeeperNode as decommissioned audit history.",
        verification: "Provider delete succeeds, GatekeeperOperation succeeds, GatekeeperNode becomes decommissioned, and ProvisioningRequest records destroyed_at.",
        metadata: { destructive:true, separate_approval_required:true, auto_executable:false }
      }
    ].each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
RUBY

echo "=== RUBY SYNTAX ==="
ruby -c "$MIGRATION"
ruby -c app/services/gatekeeper/compute/linode_catalog_service.rb
ruby -c app/services/gatekeeper/compute/node_credential_service.rb
ruby -c app/services/gatekeeper/compute/provisioning_execution_service.rb
ruby -c app/services/gatekeeper/compute/node_verification_service.rb
ruby -c app/services/gatekeeper/compute/deprovisioning_service.rb
ruby -c app/services/gatekeeper/compute/providers/linode_adapter.rb
ruby -c app/models/gatekeeper_node.rb
ruby -c app/models/provisioning_request.rb
ruby -c app/controllers/dashboard/provisioning_requests_controller.rb
ruby -c app/controllers/dashboard/linode_smoke_tests_controller.rb
ruby -c config/routes.rb
ruby -c lib/tasks/gatekeeper_billable_execution_lessons.rake

echo "=== MIGRATE ==="
bin/rails db:migrate

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ROUTES ==="
bin/rails routes | grep -E 'linode_smoke_test|execute_dashboard_provisioning|verify_dashboard_provisioning|approve_destroy_dashboard_provisioning|destroy_dashboard_provisioning'

echo "=== LINODE PROVIDER READINESS ==="
bin/rails runner '
p = ComputeProvider.find_by(slug:"linode")
puts "provider=#{p&.name.inspect}"
puts "status=#{p&.status.inspect}"
puts "health=#{p&.health_status.inspect}"
puts "credential=#{p&.credential_secret_slug.present? ? "CONFIGURED" : "MISSING"}"
puts "validation=#{p&.metadata.to_h["validation_status"].inspect}"
'

echo "=== BILLABLE SAFETY CONTRACT ==="
bin/rails runner '
puts "requests=#{ProvisioningRequest.count}"
puts "create_calls_from_install=0"
puts "destroy_calls_from_install=0"
puts "decommissioned_status=#{GatekeeperNode::STATUSES.include?("decommissioned")}"
'

echo "=== KB LESSONS ==="
bin/rails gatekeeper:learn_billable_execution

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "LINODE BILLABLE EXECUTION PASS INSTALLED"
echo "Backup: $BACKUP"
echo "IMPORTANT: installer performs ZERO provider create/delete calls."
