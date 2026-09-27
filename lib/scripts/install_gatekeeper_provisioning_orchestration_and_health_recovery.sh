#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/provisioning_orchestration_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in \
  lib/scripts/gatekeeper/deploy_project.sh \
  config/routes.rb \
  app/controllers/dashboard/compute_providers_controller.rb \
  app/views/dashboard/compute_providers/show.html.erb \
  config/initializers/lightek_dymond_dash_features.rb \
  app/models/user.rb
do
  backup "$f"
done

mkdir -p \
  app/models \
  app/services/gatekeeper/compute \
  app/controllers/dashboard \
  app/views/dashboard/provisioning_requests \
  db/migrate \
  lib/tasks

echo "==> Hardening post-deploy health check"

python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/gatekeeper/deploy_project.sh")
src = path.read_text()

old = '''echo "[7/7] Health"
HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up")"
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: healthcheck HTTP ${HTTP_CODE}"; exit 1; }
'''

new = '''echo "[7/7] Health"
HTTP_CODE=""
HEALTH_URL="https://${APP_DOMAIN}/up"
HEALTH_ATTEMPTS="${GATEKEEPER_HEALTH_ATTEMPTS:-12}"
HEALTH_SLEEP="${GATEKEEPER_HEALTH_SLEEP_SECONDS:-5}"
HEALTH_TIMEOUT="${GATEKEEPER_HEALTH_TIMEOUT_SECONDS:-10}"

for attempt in $(seq 1 "$HEALTH_ATTEMPTS"); do
  echo "Health check attempt ${attempt}/${HEALTH_ATTEMPTS}..."

  HTTP_CODE="$(
    curl -L -sS -o /dev/null -w '%{http_code}' \
      --max-time "$HEALTH_TIMEOUT" \
      "$HEALTH_URL" || true
  )"

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Health check passed."
    break
  fi

  echo "Health check returned '${HTTP_CODE:-no response}'."
  if [[ "$attempt" -lt "$HEALTH_ATTEMPTS" ]]; then
    sleep "$HEALTH_SLEEP"
  fi
done

[[ "$HTTP_CODE" == "200" ]] || {
  echo "ERROR: healthcheck failed after ${HEALTH_ATTEMPTS} attempts"
  exit 1
}
'''

if 'Health check attempt ${attempt}/${HEALTH_ATTEMPTS}...' in src:
    print("Health retry loop already installed.")
elif new in src:
    print("Health retry loop already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Replaced single-shot health check with bounded retry loop.")
else:
    raise SystemExit("ERROR: expected Gatekeeper deploy health block not found")
PY

MIGRATION="db/migrate/${STAMP}_create_provisioning_requests.rb"

cat > "$MIGRATION" <<'RUBY'
class CreateProvisioningRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :provisioning_requests do |t|
      t.string :owner_type
      t.bigint :owner_id

      t.references :subscription,
                   foreign_key: { to_table: :dymond_bank_subscriptions }

      t.references :subscription_plan,
                   foreign_key: { to_table: :dymond_bank_subscription_plans }

      t.references :subscription_infrastructure_entitlement,
                   foreign_key: true

      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.references :compute_provider, foreign_key: true
      t.references :gatekeeper_operation, foreign_key: true

      t.integer :requested_node_count, null: false, default: 1
      t.integer :estimated_monthly_cost_cents

      t.string :approval_status, null: false, default: "pending"
      t.string :execution_status, null: false, default: "draft"

      t.text :approval_reason
      t.string :approved_by
      t.datetime :approved_at

      t.string :error_class
      t.text :error_message

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :provisioning_requests, [:owner_type, :owner_id]
    add_index :provisioning_requests, :approval_status
    add_index :provisioning_requests, :execution_status
    add_index :provisioning_requests, :created_at
  end
end
RUBY

cat > app/models/provisioning_request.rb <<'RUBY'
class ProvisioningRequest < ApplicationRecord
  APPROVAL_STATUSES = %w[pending auto_approved approved rejected].freeze
  EXECUTION_STATUSES = %w[
    draft
    awaiting_provider
    awaiting_cost
    awaiting_approval
    ready
    queued
    provisioning
    succeeded
    failed
    cancelled
  ].freeze

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :subscription, class_name: "DymondBank::Subscription", optional: true
  belongs_to :subscription_plan, class_name: "DymondBank::SubscriptionPlan", optional: true
  belongs_to :subscription_infrastructure_entitlement, optional: true
  belongs_to :provisioning_profile, optional: true
  belongs_to :compute_policy, optional: true
  belongs_to :compute_provider, optional: true
  belongs_to :gatekeeper_operation, optional: true

  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :execution_status, inclusion: { in: EXECUTION_STATUSES }
  validates :requested_node_count, numericality: { only_integer: true, greater_than: 0 }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :needs_approval, -> { where(approval_status: "pending", execution_status: "awaiting_approval") }

  def approved?
    approval_status.in?(%w[auto_approved approved])
  end

  def executable?
    approved? && execution_status == "ready" && compute_provider.present?
  end
end
RUBY

cat > app/services/gatekeeper/compute/provisioning_request_builder.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ProvisioningRequestBuilder
      class NoInfrastructureEntitlement < StandardError; end

      def self.call(subscription:, estimated_monthly_cost_cents: nil, requested_by: "system")
        new(
          subscription: subscription,
          estimated_monthly_cost_cents: estimated_monthly_cost_cents,
          requested_by: requested_by
        ).call
      end

      def initialize(subscription:, estimated_monthly_cost_cents:, requested_by:)
        @subscription = subscription
        @estimated_monthly_cost_cents = estimated_monthly_cost_cents
        @requested_by = requested_by
      end

      def call
        subscriber = subscription.subscriber
        resolution = SubscriptionResolver.call(subscriber: subscriber)

        unless resolution&.entitlement
          raise NoInfrastructureEntitlement,
                "Subscription plan #{subscription.plan_id} has no infrastructure entitlement"
        end

        entitlement = resolution.entitlement
        provider, provider_error = select_provider(resolution.policy)

        request = ProvisioningRequest.create!(
          owner: subscriber,
          subscription: subscription,
          subscription_plan: subscription.plan,
          subscription_infrastructure_entitlement: entitlement,
          provisioning_profile: resolution.profile,
          compute_policy: resolution.policy,
          compute_provider: provider,
          requested_node_count: [resolution.node_quantity.to_i, 1].max,
          estimated_monthly_cost_cents: estimated_monthly_cost_cents,
          approval_status: "pending",
          execution_status: initial_execution_status(provider, estimated_monthly_cost_cents),
          metadata: {
            "requested_by" => requested_by,
            "auto_provision" => resolution.auto_provision,
            "provider_selection_error" => provider_error
          }.compact
        )

        ApprovalService.call(request: request, requested_by: requested_by)
      end

      private

      attr_reader :subscription, :estimated_monthly_cost_cents, :requested_by

      def select_provider(policy)
        return [nil, "No compute policy configured"] unless policy

        [ProviderSelector.call(policy: policy), nil]
      rescue StandardError => e
        [nil, "#{e.class}: #{e.message}"]
      end

      def initial_execution_status(provider, estimated_cost)
        return "awaiting_provider" unless provider
        return "awaiting_cost" if estimated_cost.nil?
        "awaiting_approval"
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/approval_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ApprovalService
      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        return request if request.compute_provider.blank?

        if request.estimated_monthly_cost_cents.nil?
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_cost",
            approval_reason: "Monthly cost estimate is required before automatic approval can be evaluated."
          )
          return request
        end

        policy = request.compute_policy

        if policy.blank?
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "No compute policy is attached; human approval is required."
          )
          return request
        end

        if policy.monthly_cost_ceiling_cents.present? &&
           request.estimated_monthly_cost_cents > policy.monthly_cost_ceiling_cents
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "Estimated monthly cost exceeds policy ceiling."
          )
          return request
        end

        if policy.approval_required_for?(request.estimated_monthly_cost_cents)
          request.update!(
            approval_status: "pending",
            execution_status: "awaiting_approval",
            approval_reason: "Estimated monthly cost exceeds automatic approval ceiling."
          )
        else
          request.update!(
            approval_status: "auto_approved",
            execution_status: "ready",
            approval_reason: "Automatically approved under compute policy #{policy.slug}.",
            approved_by: "nevaeh/policy",
            approved_at: Time.current
          )
        end

        request
      end

      private

      attr_reader :request, :requested_by
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/provider_validation_service.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ProviderValidationService
      READ_ONLY_CAPABILITIES = %w[regions plans images nodes].freeze

      def self.call(provider:, requested_by:)
        new(provider:, requested_by:).call
      end

      def initialize(provider:, requested_by:)
        @provider = provider
        @requested_by = requested_by
      end

      def call
        provider.update!(status: "validating")

        adapter = provider.adapter(requested_by: requested_by)
        checks = {}

        health = adapter.healthcheck
        checks["healthcheck"] = { "passed" => health[:ok] == true, "result" => health.stringify_keys }

        READ_ONLY_CAPABILITIES.each do |capability|
          next unless provider.capability?(capability)

          begin
            result = adapter.public_send(capability)
            checks[capability] = {
              "passed" => true,
              "count" => result.respond_to?(:count) ? result.count : nil
            }.compact
          rescue StandardError => e
            checks[capability] = {
              "passed" => false,
              "error_class" => e.class.name,
              "error_message" => e.message
            }
          end
        end

        passed = checks.values.all? { |check| check["passed"] == true }

        provider.update!(
          health_status: passed ? "healthy" : "degraded",
          last_healthcheck_at: Time.current,
          metadata: provider.metadata.to_h.merge(
            "validation_status" => passed ? "passed" : "failed",
            "validation_checks" => checks,
            "validated_at" => Time.current.iso8601
          )
        )

        checks
      rescue StandardError => e
        provider.update!(
          health_status: "failed",
          last_healthcheck_at: Time.current,
          metadata: provider.metadata.to_h.merge(
            "validation_status" => "failed",
            "validation_error" => "#{e.class}: #{e.message}"
          )
        )
        raise
      end

      private

      attr_reader :provider, :requested_by
    end
  end
end
RUBY

cat > app/controllers/dashboard/provisioning_requests_controller.rb <<'RUBY'
class Dashboard::ProvisioningRequestsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_request, only: %i[show approve reject]

  def index
    @requests = ProvisioningRequest.includes(
      :owner,
      :subscription_plan,
      :provisioning_profile,
      :compute_policy,
      :compute_provider
    ).recent_first.limit(200)
  end

  def show
  end

  def create
    subscription = DymondBank::Subscription.find(params.require(:subscription_id))

    request = Gatekeeper::Compute::ProvisioningRequestBuilder.call(
      subscription: subscription,
      estimated_monthly_cost_cents: params[:estimated_monthly_cost_cents].presence&.to_i,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(request),
                notice: "Provisioning request created without executing provider billing."
  rescue StandardError => e
    redirect_to dashboard_provisioning_requests_path, alert: e.message
  end

  def approve
    @request.update!(
      approval_status: "approved",
      execution_status: @request.compute_provider.present? ? "ready" : "awaiting_provider",
      approval_reason: "Approved by super administrator.",
      approved_by: current_user.email_address,
      approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning request approved. No provider resource has been created yet."
  end

  def reject
    @request.update!(
      approval_status: "rejected",
      execution_status: "cancelled",
      approval_reason: params[:reason].presence || "Rejected by super administrator.",
      approved_by: current_user.email_address,
      approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning request rejected."
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_request
    @request = ProvisioningRequest.find(params[:id])
  end
end
RUBY

cat > app/controllers/dashboard/compute_provider_validations_controller.rb <<'RUBY'
class Dashboard::ComputeProviderValidationsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def create
    provider = ComputeProvider.find(params[:compute_provider_id])

    checks = Gatekeeper::Compute::ProviderValidationService.call(
      provider: provider,
      requested_by: current_user.email_address
    )

    passed = checks.values.all? { |check| check["passed"] == true }

    redirect_to dashboard_compute_provider_path(provider),
                notice: passed ? "Read-only provider validation passed." : "Provider validation completed with failures."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]),
                alert: "Provider validation failed: #{e.message}"
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
RUBY

cat > app/views/dashboard/provisioning_requests/index.html.erb <<'ERB'
<% content_for :page_title, "Provisioning Requests" %>

<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Nevaeh · Approval Boundary · Gatekeeper</div>
  <h2>Provisioning Requests</h2>
  <p style="color:var(--dd-text-secondary)">Durable requests between a subscription entitlement and a billable provider action.</p>
</div>

<% @requests.each do |request| %>
  <%= link_to dashboard_provisioning_request_path(request), style:"text-decoration:none;color:inherit" do %>
    <div class="dd-card" style="padding:16px;margin-bottom:10px">
      <strong>Request #<%= request.id %></strong>
      · <%= request.subscription_plan&.name || "No plan" %>
      · <%= request.owner&.respond_to?(:email_address) ? request.owner.email_address : request.owner_type %>
      <div style="font-size:12px;color:var(--dd-text-secondary);margin-top:4px">
        approval=<%= request.approval_status %>
        · execution=<%= request.execution_status %>
        · provider=<%= request.compute_provider&.name || "unresolved" %>
        · estimate=<%= request.estimated_monthly_cost_cents ? number_to_currency(request.estimated_monthly_cost_cents / 100.0) : "unknown" %>
      </div>
    </div>
  <% end %>
<% end %>
ERB

cat > app/views/dashboard/provisioning_requests/show.html.erb <<'ERB'
<% content_for :page_title, "Provisioning Request ##{@request.id}" %>

<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Gatekeeper Provisioning</div>
  <h2>Request #<%= @request.id %></h2>
  <p><%= @request.subscription_plan&.name %> · <%= @request.provisioning_profile&.name %></p>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px">
  <div class="dd-card" style="padding:18px">
    <h3>Decision</h3>
    <p>Approval: <strong><%= @request.approval_status %></strong></p>
    <p>Execution: <strong><%= @request.execution_status %></strong></p>
    <p>Reason: <%= @request.approval_reason.presence || "none" %></p>
  </div>

  <div class="dd-card" style="padding:18px">
    <h3>Infrastructure</h3>
    <p>Provider: <%= @request.compute_provider&.name || "unresolved" %></p>
    <p>Profile: <%= @request.provisioning_profile&.slug || "none" %></p>
    <p>Policy: <%= @request.compute_policy&.slug || "none" %></p>
    <p>Nodes: <%= @request.requested_node_count %></p>
    <p>Estimate: <%= @request.estimated_monthly_cost_cents ? number_to_currency(@request.estimated_monthly_cost_cents / 100.0) : "unknown" %></p>
  </div>
</div>

<% if @request.approval_status == "pending" %>
  <div class="dd-card" style="padding:18px;margin-top:14px;display:flex;gap:10px">
    <%= button_to "Approve",
          approve_dashboard_provisioning_request_path(@request),
          method: :post,
          class:"dd-topbar-btn dd-btn-primary",
          data:{turbo_confirm:"Approve this provisioning request? No provider resource is created by this pass."} %>

    <%= button_to "Reject",
          reject_dashboard_provisioning_request_path(@request),
          method: :post,
          class:"dd-topbar-btn",
          data:{turbo_confirm:"Reject this provisioning request?"} %>
  </div>
<% end %>
ERB

python3 <<'PY'
from pathlib import Path

path = Path("config/routes.rb")
src = path.read_text()

block = '''resources :dashboard_provisioning_requests,
          path: "/dashboard/infrastructure/provisioning",
          controller: "dashboard/provisioning_requests",
          only: %i[index show create] do
  member do
    post :approve
    post :reject
  end
end

post "/dashboard/infrastructure/providers/:compute_provider_id/validate",
     to: "dashboard/compute_provider_validations#create",
     as: :validate_dashboard_compute_provider

'''

if 'dashboard_provisioning_requests' not in src:
    marker = 'mount DymondDash::Engine => "/dashboard"'
    if marker not in src:
        raise SystemExit("ERROR: DymondDash mount not found")
    path.write_text(src.replace(marker, block + marker, 1))
    print("Added provisioning and provider validation routes.")
else:
    print("Provisioning routes already present.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("app/controllers/dashboard/compute_providers_controller.rb")
src = path.read_text()

old = '''  def activate
    @provider.update!(status: "active")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider activated."
  end
'''

new = '''  def activate
    unless @provider.metadata.to_h["validation_status"] == "passed"
      redirect_to dashboard_compute_provider_path(@provider),
                  alert: "Provider must pass read-only validation before activation."
      return
    end

    @provider.update!(status: "active")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider activated."
  end
'''

if new in src:
    print("Provider activation validation gate already present.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Provider activation now requires validation.")
else:
    raise SystemExit("ERROR: expected ComputeProvidersController#activate not found")
PY

python3 <<'PY'
from pathlib import Path

path = Path("app/views/dashboard/compute_providers/show.html.erb")
src = path.read_text()

if "Read-only Capability Validation" not in src:
    append = '''
<div class="dd-card" style="padding:18px;margin-top:16px">
  <h3>Read-only Capability Validation</h3>
  <p style="font-size:12px;color:var(--dd-text-secondary)">
    Health, regions, plans, images and node listing only. No provisioning, resizing or deletion occurs here.
  </p>

  <%= form_with url: dashboard_compute_provider_capabilities_path(@provider), method: :patch do %>
    <% %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].each do |capability| %>
      <label style="display:block;margin:6px 0">
        <%= hidden_field_tag "capabilities[#{capability}]", "0" %>
        <%= check_box_tag "capabilities[#{capability}]", "1", @provider.capability?(capability) %>
        <%= capability.humanize %>
      </label>
    <% end %>
    <%= submit_tag "Save Capability Map", class:"dd-topbar-btn" %>
  <% end %>

  <div style="margin-top:12px">
    <%= button_to "Validate Read-only Capabilities",
          validate_dashboard_compute_provider_path(@provider),
          method: :post,
          class:"dd-topbar-btn dd-btn-primary" %>
  </div>

  <% checks = @provider.metadata.to_h["validation_checks"] || {} %>
  <% if checks.any? %>
    <div style="margin-top:12px">
      <% checks.each do |name, check| %>
        <div><strong><%= name %></strong>: <%= check["passed"] ? "PASS" : "FAIL" %></div>
      <% end %>
    </div>
  <% end %>
</div>
'''
    path.write_text(src.rstrip() + "\n" + append)
    print("Added provider capability validation UI.")
else:
    print("Provider capability validation UI already present.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("config/initializers/lightek_dymond_dash_features.rb")
src = path.read_text()

if ':provisioning_requests' not in src:
    anchor = "rescue StandardError => e"
    if anchor not in src:
        raise SystemExit("ERROR: FeatureRegistry rescue anchor not found")

    block = '''  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :provisioning_requests
    f.label       = "Provisioning Requests"
    f.icon        = "server-bolt"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [{
      label: "Provisioning Requests",
      icon: "server-bolt",
      path: "main_app.dashboard_provisioning_requests_path"
    }]
  end

'''
    path.write_text(src.replace(anchor, block + anchor, 1))
    print("Registered Provisioning Requests in DymondDash.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("app/models/user.rb")
src = path.read_text()

needle = '''      infrastructure_catalog
      subscription_plan_management
      vault
'''

replacement = '''      infrastructure_catalog
      subscription_plan_management
      provisioning_requests
      vault
'''

if "provisioning_requests" not in src:
    if needle not in src:
        raise SystemExit("ERROR: super-admin feature gate list not found")
    path.write_text(src.replace(needle, replacement, 1))
    print("Added provisioning_requests to super-admin feature gate.")
PY

cat > lib/tasks/gatekeeper_provisioning_lessons.rake <<'RUBY'
namespace :gatekeeper do
  desc "Teach deployment warmup and provisioning approval boundary lessons"
  task learn_provisioning_orchestration: :environment do
    lessons = [
      {
        key: "GK-LESSON-POST-DEPLOY-HEALTH-WARMUP",
        title: "Post-deploy health checks tolerate bounded Passenger warm-up",
        capability: "deploy_project",
        symptom: "Immediately after Apache/Passenger reload, curl to /up times out with curl exit 28, while a later deployment or request succeeds.",
        cause: "The first health request can race Passenger/Rails cold startup even though Apache, migrations, assets and application boot are otherwise healthy.",
        remediation: "Retry the HTTPS /up health endpoint with bounded attempts, per-attempt timeout and sleep interval. Treat success on any bounded retry as healthy. Escalate only after all retries fail.",
        verification: "Deployment completes only after /up returns HTTP 200; persistent failures still exit nonzero.",
        metadata: {
          failure_signature: "curl: (28) Operation timed out",
          auto_executable: true,
          remediation: "bounded_health_retry"
        }
      },
      {
        key: "GK-LESSON-PROVISIONING-APPROVAL-BOUNDARY",
        title: "Subscriptions create provisioning requests before billable provider actions",
        capability: "provision_infrastructure",
        symptom: "An active subscription is entitled to dedicated infrastructure.",
        cause: "Directly turning subscription activation into provider API calls would mix billing entitlement, provider selection, cost authorization and destructive execution into one unsafe step.",
        remediation: "Resolve the subscription entitlement, create a durable ProvisioningRequest, select an eligible provider through ComputePolicy, require a known monthly cost, apply the automatic approval ceiling, and only mark the request ready when policy or a super administrator approves it. Provider execution is a separate later step.",
        verification: "The request records owner, plan, profile, policy, provider, node count, cost estimate, approval status and execution status before any billable provider API call occurs.",
        metadata: {
          auto_executable: false,
          billable_execution_separated: true,
          approval_boundary: "ProvisioningRequest"
        }
      }
    ]

    lessons.each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
RUBY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$MIGRATION"
ruby -c app/models/provisioning_request.rb
ruby -c app/services/gatekeeper/compute/provisioning_request_builder.rb
ruby -c app/services/gatekeeper/compute/approval_service.rb
ruby -c app/services/gatekeeper/compute/provider_validation_service.rb
ruby -c app/controllers/dashboard/provisioning_requests_controller.rb
ruby -c app/controllers/dashboard/compute_provider_validations_controller.rb
ruby -c app/controllers/dashboard/compute_providers_controller.rb
ruby -c config/routes.rb
ruby -c config/initializers/lightek_dymond_dash_features.rb
ruby -c app/models/user.rb
ruby -c lib/tasks/gatekeeper_provisioning_lessons.rake

echo
echo "=== SHELL SYNTAX ==="
bash -n lib/scripts/gatekeeper/deploy_project.sh

echo
echo "=== MIGRATE ==="
bin/rails db:migrate

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== ROUTES ==="
bin/rails routes | grep -E 'dashboard_provisioning_request|validate_dashboard_compute_provider'

echo
echo "=== ACCESS ==="
bin/rails runner '
sa = User.where(role:"super_admin").first
client = User.where(role:"client").first
puts "super_admin provisioning=#{sa&.can_access_feature?(:provisioning_requests).inspect}"
puts "client provisioning=#{client&.can_access_feature?(:provisioning_requests).inspect}"
puts "client susu=#{client&.can_access_feature?(:susu).inspect}"
'

echo
echo "=== HEALTH RETRY MARKER ==="
grep -n 'Health check attempt' lib/scripts/gatekeeper/deploy_project.sh

echo
echo "=== KB LESSONS ==="
bin/rails gatekeeper:learn_provisioning_orchestration

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "PROVISIONING ORCHESTRATION + HEALTH RECOVERY INSTALLED"
echo "Backup: $BACKUP"
echo
echo "No provider create/resize/destroy API call is introduced by this pass."
