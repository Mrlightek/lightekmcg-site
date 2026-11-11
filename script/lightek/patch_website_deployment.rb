#!/usr/init/env ruby
# script/lightek/patch_website_deployment.rb

path = "app/services/gatekeeper/website_deployment.rb"
unless File.exist?(path)
  abort "Error: #{path} not found. Run this from your Rails root directory."
end

system("git checkout -- #{path}")
content = File.read(path)

# Find the exact line where Net::SSH.start is called
target = "Net::SSH.start("
unless content.include?(target)
  abort "Error: Could not find `Net::SSH.start(` in #{path}."
end

# We replace the Net::SSH.start call with our conditional branch
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
        Net::SSH.start(
RUBY

updated = content.sub(target, replacement)

# Now find where the Net::SSH block closes or append the closing `end` for the `if` statement 
# right before the end of the mktmpdir block or ensure clause.
# Let's ensure the `else` block has its corresponding `end`.
# Since Net::SSH.start(...) do |ssh| ... end is a block, the `else` branch needs to close before the `ensure`.
# Let's target the closing of the Net::SSH block.
net_ssh_block_end_target = "end\n    rescue"
if updated.include?(net_ssh_block_end_target)
  updated.sub!(net_ssh_block_end_target, "end\n      end\n    rescue")
else
  # Fallback search if spacing differs
  updated.sub!("    rescue", "      end\n    rescue")
end

File.write(path, updated)
puts "Successfully patched #{path} with correct block closure!"