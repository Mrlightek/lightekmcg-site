# frozen_string_literal: true
require "json"
raise "Production runtime required" unless Rails.env.production?
raise "Explicit manual-order authorization required" unless ENV["LIGHTEK_CREATE_MANUAL_PAID_ORDER"] == "1"
actor = User.where(role: "super_admin").order(:id).first!
Gatekeeper::WebsiteDnsPublication.preflight!(hostname: "client-1.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}")
provider = ComputeProvider.find_by!(slug: "linode")
adapter = provider.adapter(requested_by: actor.email_address)
raise "Linode authentication failed" unless adapter.healthcheck.fetch(:ok)
provider.update!(status: "active", health_status: "healthy", last_healthcheck_at: Time.current)
plans = adapter.plans
selected = if ENV["LIGHTEK_AUTO_VPS_PLAN"].present?
  plans.find { |plan| plan["id"] == ENV["LIGHTEK_AUTO_VPS_PLAN"] }
else
  plans.select { |plan| plan["memory"].to_i >= 2048 && plan.dig("price", "monthly").to_f.positive? }
    .min_by { |plan| [plan.dig("price", "monthly").to_f, plan["memory"].to_i] }
end
raise "No eligible Linode plan" unless selected
cost = (selected.fetch("price").fetch("monthly").to_f * 100).round
raise "Selected Linode exceeds the $25 monthly policy ceiling" unless cost.positive? && cost <= 2500
regions = adapter.regions.select { |region| region["status"] == "ok" }
region = if ENV["LIGHTEK_AUTO_VPS_REGION"].present?
  regions.find { |candidate| candidate["id"] == ENV["LIGHTEK_AUTO_VPS_REGION"] }
else
  regions.find { |candidate| candidate["id"] == "us-east" } || regions.find { |candidate| candidate["country"] == "us" }
end
raise "No eligible Linode region" unless region
image_id = ENV["LIGHTEK_AUTO_VPS_IMAGE"].presence || "linode/ubuntu24.04"
raise "Ubuntu image unavailable" unless adapter.images.any? { |image| image["id"] == image_id }
site = LightekSettings::WebsiteIdentity.sites_for(actor).order(:id).first!
ApplicationRecord.transaction do
  profile = ProvisioningProfile.find_or_create_by!(slug: "paid_instance") do |record|
    record.assign_attributes(name: "Lightek application instance", purpose: "dedicated_application",
      os_image: image_id, cpu_cores: selected["vcpus"], memory_mb: selected["memory"], disk_gb: selected["disk"].to_i / 1024,
      services: %w[apache docker postgresql redis sidekiq], firewall_rules: %w[22/tcp 80/tcp 443/tcp], active: true)
  end
  policy = ComputePolicy.find_or_create_by!(slug: "paid_instance") do |record|
    record.assign_attributes(name: "Paid application instance", purpose: "dedicated_application",
      preferred_provider: provider, monthly_cost_ceiling_cents: 2500,
      automatic_approval_ceiling_cents: cost, allowed_regions: [region.fetch("id")], active: true)
  end
  plan = DymondBank::SubscriptionPlan.find_or_create_by!(slug: "lightek-managed-instance") do |record|
    record.assign_attributes(name: "Lightek Managed Application", price_monthly_cents: 2500, active: true)
  end
  SubscriptionInfrastructureEntitlement.find_or_create_by!(subscription_plan: plan) do |record|
    record.assign_attributes(provisioning_profile: profile, compute_policy: policy, node_quantity: 1, auto_provision: true)
  end
  LightekCommerce::Product.find_or_create_by!(site: site, slug: "lightek-managed-instance") do |record|
    record.assign_attributes(name: "Lightek Managed Application", price_cents: 2500,
      inventory_quantity: 100, published: true, product_type: "lightek_instance", subscription_plan_id: plan.id)
  end
end
# These four values are nonsecret deployment settings. The root release process
# persists them alongside the application's existing production environment.
settings = {"LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS" => cost.to_s,
  "LIGHTEK_AUTO_VPS_REGION" => region.fetch("id"), "LIGHTEK_AUTO_VPS_PLAN" => selected.fetch("id"),
  "LIGHTEK_AUTO_VPS_IMAGE" => image_id}
File.write(Rails.root.join("tmp/manual_paid_vps_config.json"), JSON.generate(settings), mode: "w", perm: 0o600)
puts "INSTANCE_CATALOG_READY plan=#{selected.fetch('id')} monthly_cost_cents=#{cost} allocation_created=false"
