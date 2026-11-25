# frozen_string_literal: true

# Authenticated Rack requests with the real application routes, views, models and
# staging service. The private Dashboard engine's layout/session boundary and the
# remote catalog are fixtures. A provider allocation in this harness fails.
require "tmpdir"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "minitest/autorun"
require "minitest/mock"

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

class User < ApplicationRecord
  def account_branding_profile = nil
end
class GatekeeperNode < ApplicationRecord
  has_many :gatekeeper_projects
end
class GatekeeperProject < ApplicationRecord
  belongs_to :gatekeeper_node, optional: true
end
class GatekeeperOperation < ApplicationRecord
  belongs_to :gatekeeper_node, optional: true
  belongs_to :gatekeeper_project, optional: true
  scope :recent_first, -> { order(id: :desc) }
end
class ProvisioningProfile < ApplicationRecord; end
class ComputePolicy < ApplicationRecord; end
module DymondBank
  class SubscriptionPlan < ApplicationRecord; end
end
module Dashboard; end

module DymondDash
  class ApplicationController < ActionController::Base
    before_action :require_fixture_session!
    helper_method :current_user, :main_app, :dymond_dash

    protected

    def require_fixture_session!
      head :unauthorized unless current_user
    end

    def current_user = User.find_by(id: session[:user_id])
    def main_app = Rails.application.routes.url_helpers
    def dymond_dash = main_app
  end
end

class FixtureSessionController < ActionController::Base

  def create
    user = User.find_by!(email_address: params.require(:email_address))
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare("fixture-password", params[:password].to_s)

    reset_session
    session[:user_id] = user.id
    head :no_content
  end
end

source = File.expand_path("../..", __dir__)
fixture = Dir.mktmpdir("staging-provisioning-dashboard-")
FileUtils.mkdir_p(File.join(fixture, "app/views/dymond_dash/layouts"))
File.write(File.join(fixture, "app/views/dymond_dash/layouts/dymond_dash.html.erb"),
  "<%= csrf_meta_tags %><% flash.each do |_, message| %><p><%= message %></p><% end %><%= yield %>")
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"
class StagingDashboardFixture < Rails::Application; end
app = StagingDashboardFixture.instance
app.config.root = fixture
app.config.eager_load = false
app.config.secret_key_base = "staging-provisioning-fixture-" * 4
app.config.logger = Logger.new(File::NULL)
app.config.hosts.clear
app.config.action_dispatch.show_exceptions = :rescuable
app.config.load_defaults 8.0
app.config.action_controller.allow_forgery_protection = true
app.initialize!
FixtureSessionController.skip_forgery_protection only: :create

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role; t.string :email_address; t.datetime :access_suspended_at }
  create_table(:compute_providers) do |t|
    %i[name slug status health_status adapter_type adapter_class credential_secret_slug].each { |field| t.string field }
  end
  create_table(:lightek_vault_secrets) do |t|
    %i[name slug secret_type environment status].each { |field| t.string field }
    t.json :access_policy
    t.datetime :disabled_at
    t.datetime :expires_at
  end
  create_table(:provisioning_requests) do |t|
    %i[owner subscription subscription_plan provisioning_profile compute_policy compute_provider gatekeeper_node gatekeeper_operation].each { |field| t.integer :"#{field}_id" }
    %i[owner_type node_label selected_region selected_plan selected_image approval_status execution_status approved_by approval_reason].each { |field| t.string field }
    %i[requested_node_count estimated_monthly_cost_cents].each { |field| t.integer field }
    %i[approved_at destroyed_at].each { |field| t.datetime field }
    t.json :metadata, default: {}
    t.timestamps
  end
  create_table(:gatekeeper_nodes) { |t| t.string :name; t.string :status }
  create_table(:gatekeeper_projects) { |t| t.integer :gatekeeper_node_id; t.string :name }
  create_table(:gatekeeper_operations) { |t| t.integer :gatekeeper_node_id; t.integer :gatekeeper_project_id }
  create_table(:subscription_plans)
  create_table(:provisioning_profiles)
  create_table(:compute_policies)
end

%w[
  models/compute_provider models/provisioning_request models/lightek_vault/secret
  services/lightek_people/lifecycle_access services/lightek_settings/site_domain
  services/gatekeeper/hosting/access services/gatekeeper/website_owner_access
  services/gatekeeper/website_deployment services/gatekeeper/compute/linode_catalog_service
  services/gatekeeper/compute/staging_requests services/gatekeeper/compute/provisioning_execution_service
  services/godaddy/dns_service services/gatekeeper/website_dns_publication
  services/gatekeeper/compute/provider services/gatekeeper/compute/providers/http_support
  services/gatekeeper/compute/providers/linode_adapter
  helpers/infrastructure_dashboard_helper controllers/dashboard/provisioning_requests_controller
  controllers/dashboard/infrastructure_controller
].each { |file| require File.join(source, "app", file) }

module LightekVault
  class Service
    def self.checkout!(**)
      raise "Unexpected Vault checkout in Dashboard fixture"
    end
  end
end

module Gatekeeper
  module Metrics
    def self.summary = { operations: 0, succeeded: 0, failed: 0, open_support_tickets: 0, human_interventions: 0 }
  end
end

# The request list authorizes and renders the real Rails controller and view.
# These unrelated associations are absent from this fixture's database.
class ProvisioningRequest
  def subscription_plan = nil
  def provisioning_profile = nil
  def compute_policy = nil
end

[Dashboard::ProvisioningRequestsController, Dashboard::InfrastructureController].each do |controller|
  controller.append_view_path File.join(source, "app/views")
end
routes_source = File.read(File.join(source, "config/routes.rb"))
provisioning_routes = routes_source[/^resources :dashboard_provisioning_requests,.*?^end/m]
raise "Missing application provisioning routes" unless provisioning_routes

app.routes.draw do
  post "/fixture/sign_in", to: "fixture_session#create"
  get "/dashboard", to: "dashboard/infrastructure#index", as: :dashboard
  get "/dashboard/infrastructure", to: "dashboard/infrastructure#index", as: :dashboard_infrastructure
  get "/dashboard/servers", to: "dashboard/infrastructure#index", as: :dashboard_servers
  get "/dashboard/servers/:id", to: "dashboard/infrastructure#index", as: :dashboard_server
  get "/dashboard/infrastructure/updates", to: "dashboard/infrastructure#index", as: :dashboard_fleet_updates
  instance_eval(File.read(File.join(source, "config/routes/release_assurance.rb"))) if File.exist?(File.join(source, "config/routes/release_assurance.rb"))
  instance_eval(provisioning_routes, File.join(source, "config/routes.rb"))
end

class StagingProvisioningDashboardChecks < ActionDispatch::IntegrationTest
  HOSTNAME = "batch-d-msp-r1.staging.lightekmcg.com"
  CATALOG = {
    "regions" => [{ "id" => "us-east", "status" => "ok" }],
    "images" => [{ "id" => "linode/ubuntu24.04" }],
    "plans" => [{ "id" => "g6-standard-2", "monthly_cents" => 2400, "vcpus" => 2, "memory" => 4096, "disk" => 81920 }]
  }.freeze
  CREDENTIALS = {
    "staging-compute" => ["Gatekeeper::Compute::Providers::LinodeAdapter", "compute_management"],
    "staging-owner" => ["Gatekeeper::WebsiteDeployment", "website_deploy"]
  }.freeze

  setup do
    @operator = User.create!(role: "super_admin", email_address: "operator@example.test")
    @owner = User.create!(role: "client", email_address: "staging-msp@example.test")
    @provider = ComputeProvider.create!(name: "Linode", slug: "linode", status: "active", health_status: "healthy",
      adapter_type: "builtin", credential_secret_slug: "production-linode")
    CREDENTIALS.each do |slug, (consumer, purpose)|
      LightekVault::Secret.create!(name: slug, slug: slug, secret_type: "credential", environment: "staging",
        status: "active", access_policy: { "consumers" => [consumer], "purposes" => [purpose] })
    end
    @form_settings = { owner: @owner.email_address, region: "us-east", compute_vault: "staging-compute",
      owner_vault: "staging-owner", certificate_email: @operator.email_address }
    @settings = %w[ZONE OWNER REGION COMPUTE_VAULT DNS_VAULT OWNER_VAULT CERTIFICATE_EMAIL].to_h do |key|
      ["LIGHTEK_RELEASE_ASSURANCE_#{key}", nil]
    end
    @settings["GODADDY_DOMAINS"] = "lightekmcg.com"
    @previous = @settings.keys.to_h { |key| [key, ENV[key]] }
    ENV.update(@settings)
  end

  teardown do
    ENV.update(@previous) if @previous
    [ProvisioningRequest, ComputeProvider, LightekVault::Secret, User].each(&:delete_all)
  end

  test "authenticated operator follows navigation, prepares, approves and hands off by ID" do
    historical = ProvisioningRequest.create!(id: 3, owner: @operator, requested_node_count: 1,
      approval_status: "approved", execution_status: "succeeded", estimated_monthly_cost_cents: 500)
    authenticate(@operator)
    get "/dashboard/infrastructure"
    assert_response :success
    link = css_select("a").find { |item| item.text.include?("Provisioning requests") }
    assert link
    get link["href"]
    assert_response :success
    link = css_select("a").find { |item| item.text == "Prepare provisioning request" }
    assert link
    get link["href"]
    assert_response :success

    assert_select "select[name=dns_vault]", count: 0
    assert_select "input[type=submit][disabled]", count: 0
    forbid_execution do
      Gatekeeper::Compute::LinodeCatalogService.stub(:call, CATALOG) { submit_form("Prepare for approval") }
      assert_response :see_other
      follow_redirect!
      assert_response :success
      request = ProvisioningRequest.find(response.request.path.split("/").last)
      assert_equal @owner, request.owner
      assert_equal @provider, request.compute_provider
      assert_equal "production-linode", @provider.reload.credential_secret_slug
      assert_equal "staging-compute", request.metadata.dig("staging_provisioning", "vault", "compute")
      assert_nil request.metadata.dig("staging_provisioning", "vault", "dns")
      assert_equal "pending", request.approval_status
      assert_equal "awaiting_approval", request.execution_status
      assert_nil request.gatekeeper_node_id
      assert_select "h2", "Request ##{request.id}"
      assert_match HOSTNAME, response.body
      assert_equal "lightekmcg.com", request.metadata.dig("staging_provisioning", "zone")
      assert_equal ["prepared"], audit_actions(request)

      submit_form("Approve")
      assert_response :see_other
      follow_redirect!
      assert_response :success
      assert_equal "approved", request.reload.approval_status
      assert_equal "ready", request.execution_status
      assert_equal %w[prepared approved], audit_actions(request)
      assert_select "a[href=?]", "/dashboard/release_assurance?request_id=#{request.id}", text: "Choose a release candidate"
      assert_no_match "EXECUTE BILLABLE PROVISION", response.body

      post "/dashboard/infrastructure/provisioning/#{request.id}/execute", params: { authenticity_token: csrf_token }
      assert_response :see_other
      assert_nil request.reload.gatekeeper_node_id
      assert_nil request.gatekeeper_operation_id
    end
    assert_equal "succeeded", historical.reload.execution_status
    assert_equal 500, historical.estimated_monthly_cost_cents
    assert_raises(Gatekeeper::Compute::ProvisioningExecutionService::NotExecutable) do
      Gatekeeper::Compute::ProvisioningExecutionService.call(request: ProvisioningRequest.last, requested_by: @operator.email_address)
    end
  end

  test "unauthenticated and ordinary accounts cannot prepare or see staging navigation" do
    get "/dashboard/infrastructure/provisioning/new"
    assert_response :unauthorized
    authenticate(@owner)
    get "/dashboard/infrastructure"
    assert_response :success
    assert_no_match "/dashboard/infrastructure/provisioning", response.body
    post "/dashboard/infrastructure/provisioning/prepare_staging",
      params: { hostname: HOSTNAME, budget_cents: 2400, hours: 48, authenticity_token: csrf_token }
    assert_response :redirect
    assert_equal 0, ProvisioningRequest.count
  end

  test "staging quote and request adapter use the staging checkout binding" do
    authenticate(@operator)
    get "/dashboard/infrastructure/provisioning/new"
    assert_response :success
    checkout = ->(**args) do
      assert_equal "staging-compute", args.fetch(:slug)
      assert_equal "compute_management", args.fetch(:purpose)
      { "token" => "fixture-token" }
    end
    quote = ->(provider:, adapter:, **) do
      assert_equal @provider, provider
      assert_equal "fixture-token", adapter.send(:token)
      CATALOG
    end
    LightekVault::Service.stub(:checkout!, checkout) do
      Gatekeeper::Compute::LinodeCatalogService.stub(:call, quote) { submit_form("Prepare for approval") }
      assert_response :see_other
      request = ProvisioningRequest.last
      assert_equal "fixture-token", request.compute_adapter(requested_by: @operator.email_address).send(:token)
      LightekVault::Secret.find_by!(slug: "staging-compute").update!(status: "disabled")
      assert_raises(Gatekeeper::Compute::StagingRequests::Invalid) do
        request.compute_adapter(requested_by: @operator.email_address)
      end
    end
  end

  test "shows missing setup before submission and rejects an attempted production owner" do
    authenticate(@operator)
    @owner.update!(access_suspended_at: Time.current)
    @provider.update!(health_status: "unknown")
    LightekVault::Secret.where(slug: "staging-owner").update_all(status: "disabled")
    get "/dashboard/infrastructure/provisioning/new"
    assert_response :success
    assert_select "input[type=submit][disabled]"
    assert_select 'a[href="/employee/users/new"]'
    assert_select 'a[href="/dashboard/infrastructure/providers"]'
    assert_select 'a[href="/dashboard/vault"]'
    assert_select "select[name=owner] option[value=?]", @operator.email_address, count: 0
    no_quote = ->(**) { flunk "provider quote called for an invalid owner" }
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, no_quote) do
      post "/dashboard/infrastructure/provisioning/prepare_staging",
        params: @form_settings.merge(owner: @operator.email_address, hostname: HOSTNAME, budget_cents: 2400,
          hours: 48, authenticity_token: csrf_token)
    end
    assert_response :unprocessable_entity
    assert_equal 0, ProvisioningRequest.count
  end

  test "rejects staging hostnames outside managed GoDaddy domains before quoting" do
    ENV["GODADDY_DOMAINS"] = "other.example.test"
    authenticate(@operator)
    get "/dashboard/infrastructure/provisioning/new"
    assert_response :success

    unexpected_quote = ->(**) { flunk "provider catalog was called outside a managed GoDaddy domain" }
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, unexpected_quote) { submit_form("Prepare for approval") }
    assert_response :unprocessable_entity
    assert_includes response.body, "This hostname has no managed GoDaddy zone"
    assert_equal 0, ProvisioningRequest.count
  end

  test "rejects expired approvals, duplicate labels and over-budget quotes" do
    authenticate(@operator)
    get "/dashboard/infrastructure/provisioning/new"
    assert_response :success
    token = csrf_token
    path = "/dashboard/infrastructure/provisioning/prepare_staging"
    params = @form_settings.merge(hostname: HOSTNAME, budget_cents: 2400, hours: 48, authenticity_token: token)
    post path, params: params.except(:authenticity_token)
    assert_response :unprocessable_entity
    assert_equal 0, ProvisioningRequest.count
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, CATALOG) do
      post path, params: params.merge(hostname: "lightekmcg.com")
      assert_response :unprocessable_entity
      assert_equal 0, ProvisioningRequest.count
      post path, params: params.merge(compute_vault: "production-linode")
      assert_response :unprocessable_entity
      assert_equal 0, ProvisioningRequest.count
      post path, params: params.merge(budget_cents: 2300)
      assert_response :unprocessable_entity
      assert_equal 0, ProvisioningRequest.count
      post path, params: params
      assert_response :see_other
      post path, params: params
      assert_response :unprocessable_entity
      assert_equal 1, ProvisioningRequest.count
    end
    request = ProvisioningRequest.last
    request.update!(metadata: request.metadata.deep_dup.tap do |metadata|
      metadata.fetch("staging_provisioning")["expires_at"] = 1.minute.ago.iso8601
    end)
    post "/dashboard/infrastructure/provisioning/#{request.id}/approve", params: { authenticity_token: token }
    assert_response :see_other
    assert_equal "pending", request.reload.approval_status
    assert_equal ["prepared"], audit_actions(request)
  end

  private

  def authenticate(user)
    post "/fixture/sign_in", params: { email_address: user.email_address, password: "fixture-password" }
    assert_response :no_content
  end

  def csrf_token
    css_select("meta[name=csrf-token]").first["content"]
  end

  def submit_form(label)
    submit = css_select("button, input[type=submit]").find { |element| [element.text.strip, element["value"]].include?(label) }
    assert submit, "missing #{label} form"
    form = submit.ancestors("form").first
    fields = form.css("input[name]").to_h { |input| [input["name"], input["value"].to_s] }
    form.css("select[name]").each do |select|
      selected = select.at_css("option[selected]") || select.at_css("option")
      fields[select["name"]] = selected&.[]("value")
    end
    fields["hostname"] = HOSTNAME if fields.key?("hostname")
    post form["action"], params: fields
  end

  def audit_actions(request)
    request.metadata.fetch("staging_provisioning").fetch("audit").pluck("action")
  end

  def forbid_execution(&block)
    fail_if_called = ->(**) { flunk "provider allocation was attempted" }
    Gatekeeper::Compute::ProvisioningExecutionService.stub(:call, fail_if_called, &block)
  end
end

Minitest.after_run { FileUtils.remove_entry(fixture) }
