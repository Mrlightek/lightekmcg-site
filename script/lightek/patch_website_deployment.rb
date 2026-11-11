#!/usr/bin/env ruby
# script/lightek/patch_website_deployment.rb

path = "app/services/gatekeeper/website_deployment.rb"
unless File.exist?(path)
  abort "Error: #{path} not found. Run this from your Rails root directory."
end

# Reset to clean git state
system("git checkout -- #{path}")
content = File.read(path)

# Target the execute method definition
target = "def execute(config)"
unless content.include?(target)
  abort "Error: Could not find `def execute(config)` in #{path}."
end

# Insert our local execution guard clause right at the start of execute(config)
replacement = <<~'RUBY'.chomp
  def execute(config)
    if @node.metadata["local_node"] || @node.metadata[:local_node]
      @deployment_stage = "local_execution"
      output_data = StringIO.new
      Open3.popen2e({"RAILS_ENV" => Rails.env.to_s}, "bash", Rails.root.join("script/lightek/website_deploy.sh").to_s, "--config-stdin", chdir: Rails.root.to_s) do |stdin, output, wait_thr|
        stdin.write(JSON.generate(config))
        stdin.close
        output.each_line { |line| output_data.print(line); $stdout.print(line) }
        raise "Local deployment script failed with exit status #{wait_thr.value.exitstatus}" unless wait_thr.value.success?
      end
      return JSON.parse(output_data.string.lines.grep(/\{/).last || "{}")
    end
RUBY

content.sub!(target, replacement)
File.write(path, content)
puts "Successfully patched website_deployment.rb with clean top-level guard clause!"