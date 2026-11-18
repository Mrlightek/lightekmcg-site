# Run with the production Rails environment. Read-only: no installation,
# generation, credential changes, or worker selection changes.
require "json"
$stdout.sync=true

def probe_genesis(site: nil, identity: {"mode"=>"local"})
  status=Studio::Ai::Runtime.new(site:site,identity:identity).inventory(telemetry:true)
  {connected:status[:connected],reason_code:status[:reason_code],reason:status[:reason],
    device:status[:device],recipes:Array(status[:recipes]).map { |recipe| recipe.slice(:id,:ready,:reason) }}
rescue StandardError
  # Never print exceptions: worker URLs, Vault paths or credentials may be present.
  {connected:false,reason_code:"worker_configuration_invalid",
    reason:"The saved worker identity, application configuration or Vault access could not be loaded."}
end

puts JSON.generate(check:"studio_genesis",
  local_endpoint_configured:ENV["STUDIO_AI_URL"].present?,local:probe_genesis)

site_ids=StudioProject.where.not(site_id:nil).distinct.limit(100).pluck(:site_id)
DymondSite::Site.where(id:site_ids).find_each do |site|
  identity=site.manifest.to_h["studio_ai_worker"]
  next unless identity
  puts JSON.generate(check:"studio_genesis_saved_worker",site_id:site.id,
    mode:identity["mode"]=="local" ? "local" : "managed",result:probe_genesis(site:site,identity:identity))
end
