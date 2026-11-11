#!/usr/bin/env ruby
path = "app/services/gatekeeper/website_deployment.rb"
system("git checkout -- #{path}")
content = File.read(path)

# We will insert our local execution handler right before Net::SSH.start 
# and use a local flag variable to decide whether to run SSH or local bash script.
target = "Net::SSH.start("

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
        # Bypass remote SSH execution block entirely for local nodes
        ssh = nil
      else
        Net::SSH.start(
RUBY

content.sub!(target, replacement)

# Now, we need to close the `if` statement right after the `Net::SSH.start` block closes.
# Since Net::SSH.start(...) do |ssh| ... end is followed by the block body, 
# we can close the `if` right after the block's `end`.
# Let's find the end of the Net::SSH block or append an `end` right before rescue.

# To make this 100% foolproof without counting braces:
# Let's insert the `end` right before the line containing `rescue` that handles deployment errors.
if content.include?("rescue => e")
  content.sub!("rescue => e", "end\n    rescue => e")
elsif content.include?("rescue")
  content.sub!("rescue", "end\n    rescue")
end

File.write(path, content)
puts "Successfully patched website_deployment.rb with clean conditional bypass!"