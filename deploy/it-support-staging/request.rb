# frozen_string_literal: true

require "json"

action, actor_id, hostname = ARGV.reject { |arg| arg == "--" }
abort "Usage: bin/rails runner deploy/it-support-staging/request.rb inspect|prepare ACTOR_ID STAGING_HOST" unless
  %w[inspect prepare].include?(action) && actor_id&.match?(/\A[1-9][0-9]*\z/)

actor = User.find(actor_id)
Gatekeeper::WebsiteDeployment.authorize!(actor)
abort "Active operator required" unless LightekPeople::LifecycleAccess.active?(actor)
abort "Install the Gatekeeper staging provisioning bootstrap before preparing a request" unless
  defined?(Gatekeeper::Compute::StagingRequests)

staging = Gatekeeper::Compute::StagingRequests
zone = ENV.fetch("LIGHTEK_RELEASE_ASSURANCE_ZONE", "")
abort "Use a Batch D hostname in the configured staging zone" unless
  zone.match?(/\Astaging\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/) &&
    hostname&.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.#{Regexp.escape(zone)}\z/)

matches = ProvisioningRequest.where(node_label: hostname.split(".").first).where(destroyed_at: nil)
  .where.not(execution_status: "cancelled").order(:id)
if action == "prepare" && !matches.exists?
  staging.prepare!(actor: actor, hostname: hostname, budget_cents: 2400, hours: 48)
end

if action == "inspect"
  matches = matches.or(ProvisioningRequest.where(destroyed_at: nil).where.not(execution_status: "cancelled")
    .where("metadata @> ?", { release_assurance_staging: true }.to_json).order(:id))
end

requests = matches.reload.map do |request|
  binding = request.metadata.to_h[staging::METADATA_KEY].to_h
  { request_id: request.id, staging_hostname: binding["hostname"], matches_requested_host: binding["hostname"] == hostname,
    owner_type: request.owner_type, owner_id: request.owner_id, provider_id: request.compute_provider_id,
    region: request.selected_region, plan: request.selected_plan, image: request.selected_image,
    nodes: request.requested_node_count, node_id: request.gatekeeper_node_id, expires_at: binding["expires_at"],
    monthly_estimate_cents: request.estimated_monthly_cost_cents, budget_cents: binding["budget_cents"],
    approval: request.approval_status, execution: request.execution_status }
end

provider = ComputeProvider.find_by(slug: staging::PROVIDER_SLUG)
puts JSON.pretty_generate(hostname: hostname, requests: requests, provider: provider && {
  id: provider.id, status: provider.status, health: provider.health_status
})
