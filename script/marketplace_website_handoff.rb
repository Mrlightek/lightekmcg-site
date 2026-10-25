# frozen_string_literal: true
# Captures the existing website/deployment code and node inventory for the
# implementation handoff. No allocation, deployment, payment or source edits.
require "json"
require "digest"
require "fileutils"
require "open3"
abort "Development environment required" unless Rails.env.development?
stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")
root = Rails.root
out = root.join("tmp", "marketplace_website_handoff", stamp)
FileUtils.mkdir_p(out, mode: 0o700)
files = {}
paths = %w[
  app/services/marlon/manifest.rb app/services/marlon/provision_handler.rb
  app/services/marlon/provisioning.rb app/services/gatekeeper/compute
  app/services/godaddy app/services/godaddy.rb app/models/gatekeeper_node.rb
  app/models/provisioning_request.rb app/models/compute_provider.rb
  app/models/provisioning_profile.rb app/models/compute_policy.rb
  app/controllers/dashboard/provisioning_requests_controller.rb
  app/services/lightek_marketplace config/initializers/marlon_provisioning.rb
  config/initializers/lightek_marketplace_delivery.rb
  config/initializers/lightek_marketplace_checkout_settlement.rb
  Dockerfile docker-compose.yml compose.yml config/deploy.rb
]
paths.each do |relative|
  path = root.join(relative)
  candidates = path.directory? ? path.glob("**/*.rb") : [path]
  candidates.each do |source|
    next unless source.file?
    files["host/#{source.relative_path_from(root)}"] = source.to_s
  end
end
%w[dymond_site dymond_theme].each do |gem_name|
  spec = Gem.loaded_specs[gem_name]
  next unless spec
  gem_root = Pathname.new(spec.full_gem_path)
  patterns = ["app/models/**/*.rb", "lib/**/*.rb", "app/views/**/*.erb", "config/routes.rb"]
  patterns.each do |pattern|
    gem_root.glob(pattern).each do |source|
      next unless source.file?
      files["#{gem_name}/#{source.relative_path_from(gem_root)}"] = source.to_s
    end
  end
end
inventory = {}
ActiveRecord::Base.while_preventing_writes do
  {
    "GatekeeperNode" => %w[id name hostname ip_address status provider purpose],
    "ComputeProvider" => %w[id name slug status health_status],
    "ProvisioningProfile" => %w[id name slug purpose status]
  }.each do |name, allowed|
    klass = name.safe_constantize
    next unless klass && klass.table_exists?
    columns = allowed & klass.column_names
    inventory[name] = klass.order(:id).limit(30).map { |row| row.attributes.slice(*columns) }
  end
end
report = {
  "collected_at" => Time.now.utc.iso8601,
  "inventory" => inventory,
  "source_sha256" => files.transform_values { |path| Digest::SHA256.file(path).hexdigest },
  "limits" => "Source and read-only inventory only. No server authentication, deployment, DNS, TLS, payment or health checks performed."
}
report_path = out.join("handoff.json")
report_path.write(JSON.pretty_generate(report))
files["handoff.json"] = report_path.to_s
# Include the previous suite summary and a bounded failure excerpt, not the
# entire application log. Exit 124 is a timeout, never an assertion result.
previous = root.glob("tmp/marketplace_rc/*/report.json").sort.last
if previous
  files["prior_rc_report.json"] = previous.to_s
  log = previous.dirname.join("full_application_suite.log")
  if log.file?
    selected = []
    remaining = 0
    File.foreach(log) do |line|
      remaining = 8 if line.match?(/\A(?:Failure:|Error:|Finished in |\d+ runs,|RC check timed out)/)
      if remaining.positive?
        selected << line
        remaining -= 1
      end
      break if selected.length >= 600
    end
    excerpt = out.join("full_suite_failure_excerpt.txt")
    excerpt.write(selected.first(600).join)
    files["full_suite_failure_excerpt.txt"] = excerpt.to_s
  end
end
manifest = out.join("files.json")
manifest.write(JSON.generate(files))
archive = out.join("website-delivery-source.zip")
program = <<~PY
  import json,sys,zipfile
  files=json.load(open(sys.argv[1]))
  with zipfile.ZipFile(sys.argv[2],'w',zipfile.ZIP_DEFLATED) as z:
    for name,path in files.items(): z.write(path,name)
PY
stdout, stderr, status = Open3.capture3("python3", "-c", program, manifest.to_s, archive.to_s)
abort "Source capture failed: #{stderr}" unless status.success?
puts "WEBSITE_DELIVERY_SOURCE=#{archive}"
puts "Selected source and node inventory only; no resources created or deployed."
