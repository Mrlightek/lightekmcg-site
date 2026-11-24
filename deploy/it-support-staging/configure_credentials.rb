# frozen_string_literal: true

require "yaml"

domain = ARGV.last
abort "Expected an isolated staging hostname" unless domain&.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/)
abort "Expected this staging installation's native checkout" unless
  Rails.root.to_s.start_with?("/opt/lightek-sites/#{domain}/") && ItRemoteSupportSession.available? &&
    ItRemoteSupportTransfer.table_exists? && ItRemoteSupportRecording.table_exists?
if ARGV.include?("--check")
  puts "Verified Batch D migrations on the isolated staging instance"
  exit
end

secret = STDIN.read.strip
abort "Expected a fresh staging TURN secret" unless secret.match?(/\A[a-f0-9]{64}\z/)
credentials = Rails.application.credentials
settings = credentials.config.deep_stringify_keys
settings["it_remote_support"] = settings.fetch("it_remote_support", {}).merge(
  "stun_urls" => ["stun:#{domain}:3479"], "turn_urls" => ["turn:#{domain}:3479?transport=udp", "turns:#{domain}:5350?transport=tcp"],
  "turn_secret" => secret, "clamd_port" => 3310
)
credentials.write(YAML.dump(settings))
puts "Updated staging Rails encrypted credentials"
