#!/usr/bin/env ruby
# script/lightek/patch_website_deployment.rb

path = "app/services/gatekeeper/website_deployment.rb"
unless File.exist?(path)
  abort "Error: #{path} not found. Run this from your Rails root directory."
end

content = File.read(path)

# Remove any previous incomplete patch if present
content.gsub!(/\s*if @node\.metadata\["local_node"\].*?end\s*else\s*Net::SSH\.start/m, "        Net::SSH.start")

target = "Net::SSH.start"
replacement = <<~'RUBY'.chomp
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
        Net::SSH.start
RUBY

if content.include?(target)
  updated = content.sub(target, replacement)
  File.write(path, updated)
  puts "Successfully updated #{path} with robust local node execution support!"
else
  abort "Error: Could not find `Net::SSH.start` target in #{path}."
end