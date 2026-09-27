#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/infrastructure_catalog_${STAMP}"
mkdir -p "$BACKUP"

for f in app/models/user.rb config/routes.rb config/initializers/lightek_dymond_dash_features.rb app/models/gatekeeper_node.rb; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

mkdir -p app/models app/services/gatekeeper/compute app/controllers/dashboard app/views/dashboard/infrastructure_catalog app/views/dashboard/subscription_plans db/migrate lib/tasks

MIGRATION="db/migrate/${STAMP}_create_infrastructure_catalog.rb"

cat > "$MIGRATION" <<'RUBY'
class CreateInfrastructureCatalog < ActiveRecord::Migration[8.0]
  def change
    create_table :provisioning_profiles do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :purpose, null: false
      t.string :os_image, null: false, default: "ubuntu-24.04"
      t.integer :cpu_cores
      t.integer :memory_mb
      t.integer :disk_gb
      t.boolean :backups_enabled, null: false, default: true
      t.boolean :monitoring_enabled, null: false, default: true
      t.jsonb :services, null: false, default: []
      t.jsonb :firewall_rules, null: false, default: []
      t.jsonb :configuration, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :provisioning_profiles, :slug, unique: true

    create_table :compute_policies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :purpose, null: false
      t.references :preferred_provider, foreign_key: { to_table: :compute_providers }
      t.references :fallback_provider, foreign_key: { to_table: :compute_providers }
      t.integer :monthly_cost_ceiling_cents
      t.integer :automatic_approval_ceiling_cents
      t.jsonb :allowed_regions, null: false, default: []
      t.jsonb :required_capabilities, null: false, default: []
      t.jsonb :rules, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :compute_policies, :slug, unique: true

    create_table :subscription_infrastructure_entitlements do |t|
      t.references :subscription_plan, null: false, foreign_key: { to_table: :dymond_bank_subscription_plans }
      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.integer :node_quantity, null: false, default: 0
      t.boolean :auto_provision, null: false, default: false
      t.jsonb :feature_entitlements, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :subscription_infrastructure_entitlements, :subscription_plan_id, unique: true, name: "idx_subscription_infra_entitlements_plan"

    change_table :gatekeeper_nodes, bulk: true do |t|
      t.references :compute_provider, foreign_key: true
      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.string :provider_resource_id
      t.string :owner_type
      t.bigint :owner_id
      t.string :purpose
      t.string :plan
      t.string :image
      t.string :public_ipv6
      t.string :private_ip
      t.integer :estimated_monthly_cost_cents
    end
    add_index :gatekeeper_nodes, [:owner_type, :owner_id]
    add_index :gatekeeper_nodes, :provider_resource_id
  end
end
RUBY

cat > app/models/provisioning_profile.rb <<'RUBY'
class ProvisioningProfile < ApplicationRecord
  validates :name, :slug, :purpose, :os_image, presence: true
  validates :slug, uniqueness: true
  scope :active, -> { where(active: true) }

  has_many :gatekeeper_nodes, dependent: :restrict_with_error
  has_many :subscription_infrastructure_entitlements, dependent: :restrict_with_error
end
RUBY

cat > app/models/compute_policy.rb <<'RUBY'
class ComputePolicy < ApplicationRecord
  belongs_to :preferred_provider, class_name: "ComputeProvider", optional: true
  belongs_to :fallback_provider, class_name: "ComputeProvider", optional: true

  has_many :gatekeeper_nodes, dependent: :restrict_with_error
  has_many :subscription_infrastructure_entitlements, dependent: :restrict_with_error

  validates :name, :slug, :purpose, presence: true
  validates :slug, uniqueness: true
  scope :active, -> { where(active: true) }

  def approval_required_for?(monthly_cost_cents)
    automatic_approval_ceiling_cents.blank? || monthly_cost_cents.to_i > automatic_approval_ceiling_cents
  end
end
RUBY

cat > app/models/subscription_infrastructure_entitlement.rb <<'RUBY'
class SubscriptionInfrastructureEntitlement < ApplicationRecord
  belongs_to :subscription_plan, class_name: "DymondBank::SubscriptionPlan"
  belongs_to :provisioning_profile, optional: true
  belongs_to :compute_policy, optional: true

  validates :subscription_plan_id, uniqueness: true
  validates :node_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
RUBY

cat > app/services/gatekeeper/compute/provider_selector.rb <<'RUBY'
module Gatekeeper
  module Compute
    class ProviderSelector
      class NoEligibleProvider < StandardError; end

      def self.call(policy:)
        candidates = [policy.preferred_provider, policy.fallback_provider].compact.uniq
        provider = candidates.find do |candidate|
          next false unless candidate.status == "active"
          next false unless %w[healthy unknown].include?(candidate.health_status)
          Array(policy.required_capabilities).all? { |capability| candidate.capability?(capability) }
        end

        provider || raise(NoEligibleProvider, "No active provider satisfies compute policy #{policy.slug}")
      end
    end
  end
end
RUBY

cat > app/services/gatekeeper/compute/subscription_resolver.rb <<'RUBY'
module Gatekeeper
  module Compute
    class SubscriptionResolver
      Resolution = Data.define(:subscription, :plan, :entitlement, :profile, :policy, :node_quantity, :auto_provision)

      def self.call(subscriber:)
        subscription = DymondBank::Subscription
          .where(subscriber: subscriber)
          .where(status: %w[trialing active])
          .order(created_at: :desc)
          .first
        return unless subscription

        entitlement = SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id: subscription.plan_id)

        Resolution.new(
          subscription,
          subscription.plan,
          entitlement,
          entitlement&.provisioning_profile,
          entitlement&.compute_policy,
          entitlement&.node_quantity.to_i,
          entitlement&.auto_provision? || false
        )
      end
    end
  end
end
RUBY

python3 <<'PY'
from pathlib import Path
p = Path("app/models/gatekeeper_node.rb")
s = p.read_text()
anchor = '  has_many :gatekeeper_projects, dependent: :restrict_with_error\n  has_many :gatekeeper_operations, dependent: :restrict_with_error\n'
insert = anchor + '\n  belongs_to :compute_provider, optional: true\n  belongs_to :provisioning_profile, optional: true\n  belongs_to :compute_policy, optional: true\n  belongs_to :owner, polymorphic: true, optional: true\n'
if "belongs_to :compute_provider" not in s:
    if anchor not in s:
        raise SystemExit("ERROR: GatekeeperNode association anchor not found")
    p.write_text(s.replace(anchor, insert, 1))
PY

cat > app/controllers/dashboard/infrastructure_catalog_controller.rb <<'RUBY'
class Dashboard::InfrastructureCatalogController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @profiles = ProvisioningProfile.order(:name)
    @policies = ComputePolicy.includes(:preferred_provider, :fallback_provider).order(:name)
    @nodes = GatekeeperNode.includes(:compute_provider, :provisioning_profile, :compute_policy).order(:name)
  end

  def create_profile
    ProvisioningProfile.create!(profile_params)
    redirect_to dashboard_infrastructure_catalog_path, notice: "Provisioning profile created."
  rescue StandardError => e
    redirect_to dashboard_infrastructure_catalog_path, alert: e.message
  end

  def create_policy
    ComputePolicy.create!(policy_params)
    redirect_to dashboard_infrastructure_catalog_path, notice: "Compute policy created."
  rescue StandardError => e
    redirect_to dashboard_infrastructure_catalog_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def profile_params
    raw = params.require(:provisioning_profile).permit(:name,:slug,:purpose,:os_image,:cpu_cores,:memory_mb,:disk_gb,:services,:firewall_rules).to_h
    raw["services"] = raw["services"].to_s.lines.map(&:strip).reject(&:blank?)
    raw["firewall_rules"] = raw["firewall_rules"].to_s.lines.map(&:strip).reject(&:blank?)
    raw
  end

  def policy_params
    raw = params.require(:compute_policy).permit(:name,:slug,:purpose,:preferred_provider_id,:fallback_provider_id,:monthly_cost_ceiling_cents,:automatic_approval_ceiling_cents,:allowed_regions,:required_capabilities).to_h
    raw["allowed_regions"] = raw["allowed_regions"].to_s.split(",").map(&:strip).reject(&:blank?)
    raw["required_capabilities"] = raw["required_capabilities"].to_s.split(",").map(&:strip).reject(&:blank?)
    raw
  end
end
RUBY

cat > app/controllers/dashboard/subscription_plans_controller.rb <<'RUBY'
class Dashboard::SubscriptionPlansController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_plan, only: %i[edit update destroy]

  def index
    @plans = DymondBank::SubscriptionPlan.order(:sort_order, :name)
  end

  def new
    @plan = DymondBank::SubscriptionPlan.new(active: true)
    load_dependencies
  end

  def create
    @plan = DymondBank::SubscriptionPlan.create!(plan_params)
    sync_entitlement!(@plan)
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan created."
  rescue StandardError => e
    @plan ||= DymondBank::SubscriptionPlan.new(plan_params)
    load_dependencies
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def edit
    load_dependencies
  end

  def update
    @plan.update!(plan_params)
    sync_entitlement!(@plan)
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan updated."
  rescue StandardError => e
    load_dependencies
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @plan.destroy!
    redirect_to dashboard_subscription_plans_path, notice: "Subscription plan deleted."
  rescue StandardError => e
    redirect_to dashboard_subscription_plans_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_plan
    @plan = DymondBank::SubscriptionPlan.find(params[:id])
  end

  def load_dependencies
    @profiles = ProvisioningProfile.active.order(:name)
    @policies = ComputePolicy.active.order(:name)
  end

  def plan_params
    params.require(:subscription_plan).permit(:slug,:name,:description,:price_monthly_cents,:price_annual_cents,:currency,:active,:sort_order)
  end

  def sync_entitlement!(plan)
    raw = params.fetch(:infrastructure_entitlement, {}).permit(:provisioning_profile_id,:compute_policy_id,:node_quantity,:auto_provision,:feature_entitlements).to_h
    features = raw.delete("feature_entitlements").to_s.split(",").map(&:strip).reject(&:blank?)
    entitlement = SubscriptionInfrastructureEntitlement.find_or_initialize_by(subscription_plan_id: plan.id)
    entitlement.assign_attributes(raw.merge("feature_entitlements" => features))
    entitlement.save!
  end
end
RUBY

cat > app/controllers/dashboard/compute_provider_capabilities_controller.rb <<'RUBY'
class Dashboard::ComputeProviderCapabilitiesController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def update
    provider = ComputeProvider.find(params[:compute_provider_id])
    capabilities = params.fetch(:capabilities, {}).to_unsafe_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    provider.update!(capabilities: provider.capabilities.to_h.merge(capabilities), status: "validating")
    redirect_to dashboard_compute_provider_path(provider), notice: "Capabilities updated; provider is validating."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]), alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
RUBY

cat > app/views/dashboard/infrastructure_catalog/index.html.erb <<'ERB'
<% content_for :page_title, "Infrastructure Catalog" %>
<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Nevaeh · Gatekeeper · DymondBank</div>
  <h2>Infrastructure Catalog</h2>
  <p style="color:var(--dd-text-secondary)">Reusable provisioning profiles, compute policy, and managed node inventory.</p>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px">
  <div class="dd-card" style="padding:20px">
    <h3>Provisioning Profiles</h3>
    <% @profiles.each do |p| %>
      <p><strong><%= p.name %></strong><br><small><%= p.purpose %> · <%= p.cpu_cores || "?" %> CPU · <%= p.memory_mb || "?" %> MB</small></p>
    <% end %>

    <h4>Create Profile</h4>
    <%= form_with url: dashboard_infrastructure_profiles_path do %>
      <%= text_field_tag "provisioning_profile[name]", nil, placeholder:"Name", required:true %>
      <%= text_field_tag "provisioning_profile[slug]", nil, placeholder:"Slug", required:true %>
      <%= text_field_tag "provisioning_profile[purpose]", nil, placeholder:"Purpose", required:true %>
      <%= text_field_tag "provisioning_profile[os_image]", "ubuntu-24.04" %>
      <%= number_field_tag "provisioning_profile[cpu_cores]", nil, placeholder:"CPU cores" %>
      <%= number_field_tag "provisioning_profile[memory_mb]", nil, placeholder:"Memory MB" %>
      <%= number_field_tag "provisioning_profile[disk_gb]", nil, placeholder:"Disk GB" %>
      <%= text_area_tag "provisioning_profile[services]", nil, placeholder:"Services, one per line" %>
      <%= text_area_tag "provisioning_profile[firewall_rules]", nil, placeholder:"Firewall rules, one per line" %>
      <%= submit_tag "Create Profile", class:"dd-topbar-btn dd-btn-primary" %>
    <% end %>
  </div>

  <div class="dd-card" style="padding:20px">
    <h3>Compute Policies</h3>
    <% @policies.each do |p| %>
      <p><strong><%= p.name %></strong><br><small>preferred=<%= p.preferred_provider&.name || "automatic" %> · fallback=<%= p.fallback_provider&.name || "none" %></small></p>
    <% end %>

    <h4>Create Policy</h4>
    <%= form_with url: dashboard_infrastructure_policies_path do %>
      <%= text_field_tag "compute_policy[name]", nil, placeholder:"Name", required:true %>
      <%= text_field_tag "compute_policy[slug]", nil, placeholder:"Slug", required:true %>
      <%= text_field_tag "compute_policy[purpose]", nil, placeholder:"Purpose", required:true %>
      <%= select_tag "compute_policy[preferred_provider_id]", options_from_collection_for_select(ComputeProvider.order(:name), :id, :name), include_blank:"Automatic" %>
      <%= select_tag "compute_policy[fallback_provider_id]", options_from_collection_for_select(ComputeProvider.order(:name), :id, :name), include_blank:"None" %>
      <%= number_field_tag "compute_policy[monthly_cost_ceiling_cents]", nil, placeholder:"Monthly ceiling cents" %>
      <%= number_field_tag "compute_policy[automatic_approval_ceiling_cents]", nil, placeholder:"Auto approval cents" %>
      <%= text_field_tag "compute_policy[allowed_regions]", nil, placeholder:"Regions, comma-separated" %>
      <%= text_field_tag "compute_policy[required_capabilities]", nil, placeholder:"Capabilities, comma-separated" %>
      <%= submit_tag "Create Policy", class:"dd-topbar-btn dd-btn-primary" %>
    <% end %>
  </div>
</div>
ERB

cat > app/views/dashboard/subscription_plans/index.html.erb <<'ERB'
<% content_for :page_title, "Subscription Plans" %>
<div style="display:flex;justify-content:space-between;align-items:center">
  <div><h2>Subscription Plans</h2><p>Pricing plus infrastructure/service entitlements.</p></div>
  <%= link_to "New Plan", new_dashboard_subscription_plan_path, class:"dd-topbar-btn dd-btn-primary" %>
</div>

<% @plans.each do |plan| %>
  <% entitlement = SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id: plan.id) %>
  <div class="dd-card" style="padding:18px;margin:12px 0">
    <strong><%= plan.name %></strong>
    <div><%= plan.slug %> · $<%= plan.price_monthly_cents.to_i / 100.0 %>/mo · <%= plan.active? ? "active" : "inactive" %></div>
    <small>profile=<%= entitlement&.provisioning_profile&.slug || "none" %> · policy=<%= entitlement&.compute_policy&.slug || "none" %> · nodes=<%= entitlement&.node_quantity.to_i %> · auto=<%= entitlement&.auto_provision? || false %></small>
    <div><%= link_to "Edit", edit_dashboard_subscription_plan_path(plan), class:"dd-topbar-btn" %></div>
  </div>
<% end %>
ERB

cat > app/views/dashboard/subscription_plans/_form.html.erb <<'ERB'
<%= form_with model:plan, url:(plan.persisted? ? dashboard_subscription_plan_path(plan) : dashboard_subscription_plans_path) do |f| %>
  <%= f.text_field :name, placeholder:"Plan name", required:true %>
  <%= f.text_field :slug, placeholder:"Slug", required:true %>
  <%= f.text_area :description, placeholder:"Description" %>
  <%= f.number_field :price_monthly_cents, placeholder:"Monthly cents", required:true %>
  <%= f.number_field :price_annual_cents, placeholder:"Annual cents", required:true %>
  <%= f.text_field :currency, value:(plan.currency.presence || "usd") %>
  <%= f.number_field :sort_order, value:(plan.sort_order || 0) %>
  <label><%= f.check_box :active %> Active</label>

  <% entitlement = SubscriptionInfrastructureEntitlement.find_or_initialize_by(subscription_plan_id:plan.id) %>
  <h3>Infrastructure Entitlement</h3>
  <%= select_tag "infrastructure_entitlement[provisioning_profile_id]", options_from_collection_for_select(@profiles,:id,:name,entitlement.provisioning_profile_id), include_blank:"No dedicated infrastructure" %>
  <%= select_tag "infrastructure_entitlement[compute_policy_id]", options_from_collection_for_select(@policies,:id,:name,entitlement.compute_policy_id), include_blank:"No compute policy" %>
  <%= number_field_tag "infrastructure_entitlement[node_quantity]", entitlement.node_quantity || 0, min:0 %>
  <label><%= check_box_tag "infrastructure_entitlement[auto_provision]", "1", entitlement.auto_provision? %> Auto-provision when subscription activates</label>
  <%= text_field_tag "infrastructure_entitlement[feature_entitlements]", Array(entitlement.feature_entitlements).join(", "), placeholder:"Features, comma-separated" %>
  <%= f.submit class:"dd-topbar-btn dd-btn-primary" %>
<% end %>
ERB

cat > app/views/dashboard/subscription_plans/new.html.erb <<'ERB'
<% content_for :page_title, "New Subscription Plan" %>
<div class="dd-card" style="padding:20px;max-width:760px"><h2>New Subscription Plan</h2><%= render "form", plan:@plan %></div>
ERB

cat > app/views/dashboard/subscription_plans/edit.html.erb <<'ERB'
<% content_for :page_title, "Edit Subscription Plan" %>
<div class="dd-card" style="padding:20px;max-width:760px"><h2>Edit <%= @plan.name %></h2><%= render "form", plan:@plan %></div>
ERB

python3 <<'PY'
from pathlib import Path
p=Path("config/routes.rb")
s=p.read_text()
block='''get "/dashboard/infrastructure/catalog", to: "dashboard/infrastructure_catalog#index", as: :dashboard_infrastructure_catalog
post "/dashboard/infrastructure/profiles", to: "dashboard/infrastructure_catalog#create_profile", as: :dashboard_infrastructure_profiles
post "/dashboard/infrastructure/policies", to: "dashboard/infrastructure_catalog#create_policy", as: :dashboard_infrastructure_policies

resources :dashboard_subscription_plans,
          path: "/dashboard/subscriptions/plans",
          controller: "dashboard/subscription_plans"

patch "/dashboard/infrastructure/providers/:compute_provider_id/capabilities",
      to: "dashboard/compute_provider_capabilities#update",
      as: :dashboard_compute_provider_capabilities

'''
if 'dashboard_infrastructure_catalog' not in s:
    marker='mount DymondDash::Engine => "/dashboard"'
    if marker not in s: raise SystemExit("ERROR: DymondDash mount not found")
    p.write_text(s.replace(marker,block+marker,1))
PY

python3 <<'PY'
from pathlib import Path
p=Path("app/models/user.rb")
s=p.read_text()
needle='''      compute_provider_management
      vault
'''
replacement='''      compute_provider_management
      infrastructure_catalog
      subscription_plan_management
      vault
'''
if "infrastructure_catalog" not in s:
    if needle not in s: raise SystemExit("ERROR: infrastructure gate list not found")
    p.write_text(s.replace(needle,replacement,1))
PY

python3 <<'PY'
from pathlib import Path
p=Path("config/initializers/lightek_dymond_dash_features.rb")
s=p.read_text()
anchor='rescue StandardError => e'
blocks=''
if ':infrastructure_catalog' not in s:
    blocks += '''  DymondDash::FeatureRegistry.register do |f|
    f.slug = :infrastructure_catalog
    f.label = "Infrastructure Catalog"
    f.icon = "server"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Infrastructure Catalog", icon: "server", path: "main_app.dashboard_infrastructure_catalog_path" }]
  end

'''
if ':subscription_plan_management' not in s:
    blocks += '''  DymondDash::FeatureRegistry.register do |f|
    f.slug = :subscription_plan_management
    f.label = "Subscription Plans"
    f.icon = "credit-card"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Subscription Plans", icon: "credit-card", path: "main_app.dashboard_subscription_plans_path" }]
  end

'''
if blocks:
    if anchor not in s: raise SystemExit("ERROR: FeatureRegistry rescue anchor not found")
    p.write_text(s.replace(anchor,blocks+anchor,1))
PY

cat > lib/tasks/infrastructure_catalog.rake <<'RUBY'
namespace :infrastructure_catalog do
  task seed: :environment do
    [
      ["rails_shared","Rails Shared","shared_application",2,4096,80,%w[apache postgresql redis sidekiq],%w[22/tcp 80/tcp 443/tcp]],
      ["rails_dedicated","Rails Dedicated","dedicated_application",2,4096,80,%w[apache postgresql redis sidekiq],%w[22/tcp 80/tcp 443/tcp]],
      ["personal_cloud","Personal Cloud","personal_cloud",2,4096,80,%w[docker postgresql redis lightek_agent],%w[22/tcp 80/tcp 443/tcp]],
      ["mail_node","Mail Node","mail",2,4096,80,%w[postfix dovecot rspamd redis],%w[22/tcp 25/tcp 80/tcp 443/tcp 587/tcp 993/tcp]],
      ["worker_node","Worker Node","worker",2,4096,50,%w[redis sidekiq],%w[22/tcp]]
    ].each do |slug,name,purpose,cpu,memory,disk,services,rules|
      profile=ProvisioningProfile.find_or_initialize_by(slug:slug)
      profile.assign_attributes(name:name,purpose:purpose,os_image:"ubuntu-24.04",cpu_cores:cpu,memory_mb:memory,disk_gb:disk,services:services,firewall_rules:rules,active:true)
      profile.save!
      puts "Profile: #{profile.slug}"
    end

    linode=ComputeProvider.find_by(slug:"linode")
    ovh=ComputeProvider.find_by(slug:"ovh")

    [
      ["personal_cloud","Personal Cloud Policy","personal_cloud",ovh,linode,1000,700,%w[provision_node destroy_node]],
      ["lightek_production","Lightek Production Policy","production_application",linode,ovh,2500,1000,%w[provision_node reboot_node destroy_node]],
      ["mail","Mail Infrastructure Policy","mail",linode,ovh,2500,1000,%w[provision_node set_reverse_dns]]
    ].each do |slug,name,purpose,preferred,fallback,ceiling,auto,capabilities|
      policy=ComputePolicy.find_or_initialize_by(slug:slug)
      policy.assign_attributes(name:name,purpose:purpose,preferred_provider:preferred,fallback_provider:fallback,monthly_cost_ceiling_cents:ceiling,automatic_approval_ceiling_cents:auto,required_capabilities:capabilities,active:true)
      policy.save!
      puts "Policy: #{policy.slug}"
    end
  end

  task learn: :environment do
    a=Gatekeeper::LessonService.record!(
      key:"GK-LESSON-SUBSCRIPTION-INFRASTRUCTURE-ENTITLEMENTS",
      title:"Subscriptions map product entitlements to infrastructure policy",
      capability:"subscription_infrastructure_resolution",
      symptom:"A paid subscription needs to determine which services and infrastructure should be provisioned.",
      cause:"Billing plans and infrastructure were separate concepts, requiring humans to translate subscriptions into compute and service actions.",
      remediation:"Manage DymondBank SubscriptionPlan records through the dashboard and attach a SubscriptionInfrastructureEntitlement referencing a ProvisioningProfile, ComputePolicy, node quantity, features, and auto-provision behavior.",
      verification:"Resolve an active subscription through Gatekeeper::Compute::SubscriptionResolver and confirm its plan, profile, policy, node quantity and auto-provision setting.",
      metadata:{billing_system:"DymondBank",infrastructure_system:"Gatekeeper::Compute",auto_executable:false}
    )
    puts "Recorded lesson as KB article #{a.id}"
  end
end
RUBY

echo "=== SYNTAX ==="
ruby -c "$MIGRATION"
ruby -c app/models/provisioning_profile.rb
ruby -c app/models/compute_policy.rb
ruby -c app/models/subscription_infrastructure_entitlement.rb
ruby -c app/models/gatekeeper_node.rb
ruby -c app/services/gatekeeper/compute/provider_selector.rb
ruby -c app/services/gatekeeper/compute/subscription_resolver.rb
ruby -c app/controllers/dashboard/infrastructure_catalog_controller.rb
ruby -c app/controllers/dashboard/subscription_plans_controller.rb
ruby -c app/controllers/dashboard/compute_provider_capabilities_controller.rb
ruby -c config/routes.rb
ruby -c config/initializers/lightek_dymond_dash_features.rb
ruby -c app/models/user.rb
ruby -c lib/tasks/infrastructure_catalog.rake

echo "=== MIGRATE ==="
bin/rails db:migrate

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== SEED ==="
bin/rails infrastructure_catalog:seed

echo "=== SUBSCRIPTIONS ==="
bin/rails runner '
puts "Plans: #{DymondBank::SubscriptionPlan.count}"
DymondBank::SubscriptionPlan.order(:sort_order,:name).each do |plan|
  e=SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id:plan.id)
  puts "#{plan.id}: #{plan.slug} $#{plan.price_monthly_cents.to_i/100.0}/mo profile=#{e&.provisioning_profile&.slug || "none"}"
end
'

echo "=== ACCESS ==="
bin/rails runner '
sa=User.where(role:"super_admin").first
client=User.where(role:"client").first
puts "super_admin catalog=#{sa&.can_access_feature?(:infrastructure_catalog).inspect}"
puts "super_admin plans=#{sa&.can_access_feature?(:subscription_plan_management).inspect}"
puts "client catalog=#{client&.can_access_feature?(:infrastructure_catalog).inspect}"
puts "client plans=#{client&.can_access_feature?(:subscription_plan_management).inspect}"
puts "client susu=#{client&.can_access_feature?(:susu).inspect}"
'

echo "=== ROUTES ==="
bin/rails routes | grep -E 'dashboard_infrastructure_catalog|dashboard_subscription_plan|dashboard_compute_provider_capabilities'

echo "=== KB ==="
bin/rails infrastructure_catalog:learn

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "INFRASTRUCTURE CATALOG + SUBSCRIPTION CONTROL INSTALLED"
echo "Backup: $BACKUP"
