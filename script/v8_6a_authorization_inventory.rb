# frozen_string_literal: true
# Run: ruby script/v8_6a_authorization_inventory.rb
require "pathname"
root = Pathname.new(File.expand_path("..", __dir__))
scan_roots = [root.join("app"), root.join("config")]
ENV.fetch("V8_6A_ENGINE_ROOTS", "").split(File::PATH_SEPARATOR).each do |path|
  scan_roots << Pathname.new(path).join("app") if File.directory?(File.join(path, "app"))
end
pattern = /head\s+:forbidden|status:\s*:forbidden|authorize!|can_access_feature\?|local_only!|require_local_opt_in!|require_super_admin!|AccessDenied|Gatekeeper::AuthorizationService/
puts "V8_6A_AUTH_INVENTORY_BEGIN"
scan_roots.each do |base|
  next unless base.directory?
  Dir.glob(base.join("**", "*.rb").to_s).sort.each do |file|
    File.foreach(file).with_index(1) do |line, number|
      next unless line.match?(pattern)
      puts "#{file}:#{number}: #{line.strip[0,200]}"
    end
  end
end
puts "V8_6A_AUTH_INVENTORY_END"
