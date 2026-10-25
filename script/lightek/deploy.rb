# frozen_string_literal: true
require "optparse"
require "json"
options = {}
command = ARGV.shift
command = ARGV.shift if command == "--"
parser = OptionParser.new do |p|
  p.banner = "bin/lightek-deploy register|preview|run|provision [options]"
  %w[actor-id owner-id node-id request-id].each { |key| p.on("--#{key} ID", Integer) { |v| options[key.tr('-', '_').to_sym] = v } }
  %w[domain name headline description certificate-email credential-slug owner-email].each { |key| p.on("--#{key} VALUE") { |v| options[key.tr('-', '_').to_sym] = v } }
  p.on("--internal", "Internal owner becomes super_admin; customer owners remain admin") { options[:internal] = true }
  p.on("-h", "--help") { puts p; exit }
end
parser.parse!
abort parser.to_s unless %w[register preview run provision].include?(command)
abort "Choose exactly one --node-id or --request-id" unless !!options[:node_id] ^ !!options[:request_id]
actor = User.find(options.fetch(:actor_id))
Gatekeeper::WebsiteDeployment.authorize!(actor)
record = options[:node_id] ? GatekeeperNode.find(options[:node_id]) : ProvisioningRequest.find(options[:request_id])
domain = options.fetch(:domain).downcase.strip
case command
when "register"
  config = Gatekeeper::WebsiteDeployment.configuration(
    owner: User.find(options.fetch(:owner_id)), domain:,
    site_name: options.fetch(:name), headline: options.fetch(:headline), description: options.fetch(:description),
    certificate_email: options.fetch(:certificate_email), credential_slug: options.fetch(:credential_slug),
    internal: options.fetch(:internal, false), owner_email: options[:owner_email])
  puts JSON.pretty_generate(Gatekeeper::WebsiteDeployment.register!(actor:, record:, config:))
when "preview"
  puts JSON.pretty_generate(Gatekeeper::WebsiteDeployment.preview(actor:, record:, domain:))
when "run"
  abort "Use provision for a provisioning request" unless record.is_a?(GatekeeperNode)
  puts JSON.pretty_generate(Gatekeeper::WebsiteDeployment.run!(actor:, node: record, domain:))
when "provision"
  abort "provision requires --request-id" unless record.is_a?(ProvisioningRequest)
  puts JSON.pretty_generate(Gatekeeper::WebsiteDeployment.provision_and_run!(actor:, request: record, domain:))
end
