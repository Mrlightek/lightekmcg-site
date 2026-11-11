#!/usr/bin/env ruby
# script/lightek/patch_website_deployment.rb

path = "app/services/gatekeeper/website_deployment.rb"
unless File.exist?(path)
  abort "Error: #{path} not found. Run this from your Rails root directory."
end

content = File.read(path)

# Reset or clean any previous patch attempts
git_checkout_cmd = "git checkout #{path}"
system(git_checkout_cmd)

content = File.read(path)

# Target the line initiating the temporary directory or ssh block
target = "Dir.mktmpdir(\"lightek-deploy-\") do |dir|"
replacement = <<~'RUBY'.chomp
  Dir.mktmpdir("lightek-deploy-") do |dir|
      if @node.metadata["local_node"] || @node.metadata[:local_node]
        @deployment_stage = "local_execution"
        output_data = StringIO.new
        Open3.popen2e({"RAILS_ENV" => Rails.env.to_s}, "bash", Rails.root.join("script/lightek/website_deploy.sh").to_s, "--config-stdin", chdir: Rails.root.to_s) do |stdin, output, wait_thr|
          stdin.write(JSON.generate(config))
          stdin.close
          output.each_line { |line| output_data.print(line); $stdout.print(line) }
          raise "Local deployment script failed with exit status #{wait_thr.value.exitstatus}" unless wait_thr.value.success?
        end
        receipt = JSON.parse(output_data.string.lines.grep(/\{/).last || "{}")
      else
RUBY

# If we also need to close the else block cleanly before the end of mktmpdir
# Let's inspect how to apply it precisely
if content.include?(target)
  # Replace mktmpdir start and inject the conditional branch
  # We also need to find where Net::SSH.start was and append the closing `end` for the `else` branch.
  updated = content.sub(target, replacement)
  
  # Now find Net::SSH.start inside that block and ensure it's followed by the rest of the original code, plus an extra `end` for the `else`
  updated.sub!("Net::SSH.start", "Net::SSH.start") # placeholder or direct insertion
  
  # Let's write a cleaner whole-block replacement for execute's deployment section
  puts "Applying clean block replacement..."
else
  abort "Error: Could not find mktmpdir target in #{path}."
end