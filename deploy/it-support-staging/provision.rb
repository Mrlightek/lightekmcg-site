# frozen_string_literal: true

require "json"
require "open3"

# Pass only IDs and a non-secret hostname. Gatekeeper retrieves authorized Vault
# credentials through the existing WebsiteDeployment consumer.
actor_id, request_id, hostname, expected_sha = ARGV.reject { |arg| arg == "--" }
abort "Usage: bin/rails runner deploy/it-support-staging/provision.rb ACTOR_ID REQUEST_ID HOSTNAME COMMIT" unless
  actor_id&.match?(/\A[1-9][0-9]*\z/) && request_id&.match?(/\A[1-9][0-9]*\z/) &&
    hostname&.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/) &&
    expected_sha&.match?(/\A[a-f0-9]{40}\z/)

sha, sha_status = Open3.capture2("git", "rev-parse", "HEAD", chdir: Rails.root.to_s)
dirty, dirty_status = Open3.capture2("git", "status", "--porcelain", chdir: Rails.root.to_s)
abort "Use a clean checkout pinned to the reviewed staging commit" unless sha_status.success? &&
  dirty_status.success? && sha.strip == expected_sha && dirty.empty?

actor = User.find(actor_id)
request = ProvisioningRequest.find(request_id)
service = Gatekeeper::WebsiteDeployment
config = service.preview(actor: actor, record: request, domain: hostname)

abort "Use a dedicated staging request named for this host" unless request.node_label == hostname.split(".").first &&
  request.owner_id == config.fetch("owner_id")
abort "Use a fresh approved provisioning request for the isolated node" unless request.executable? && request.gatekeeper_node_id.nil?

puts JSON.generate(status: "ready", hostname: hostname, source_sha: expected_sha, request_id: request.id,
  provider_id: request.compute_provider_id, plan: request.selected_plan, region: request.selected_region)
if ENV["LIGHTEK_BATCH_D_PROVISION"] == "1"
  service.provision_and_run!(actor: actor, request: request, domain: hostname)
end
