#!/usr/bin/env ruby
# script/lightek/patch_website_deployment.rb

path = "app/services/gatekeeper/website_deployment.rb"
unless File.exist?(path)
  abort "Error: #{path} not found. Run this from your Rails root directory."
end

system("git checkout -- #{path}")
content = File.read(path)

lines = content.lines
ssh_start_line_idx = lines.find_index { |l| l.include?("Net::SSH.start") }
abort "Error: Net::SSH.start line not found in #{path}." unless ssh_start_line_idx

indent = lines[ssh_start_line_idx][/^\s*/]

local_exec_code = [
  "#{indent}if @node.metadata[\"local_node\"] || @node.metadata[:local_node]\n",
  "#{indent}  @deployment_stage = \"local_execution\"\n",
  "#{indent}  output_data = StringIO.new\n",
  "#{indent}  Open3.popen2e({\"RAILS_ENV\" => Rails.env.to_s}, \"bash\", Rails.root.join(\"script/lightek/website_deploy.sh\").to_s, \"--config-stdin\", chdir: Rails.root.to_s) do |stdin, output, wait_thr|\n",
  "#{indent}    stdin.write(JSON.generate(config))\n",
  "#{indent}    stdin.close\n",
  "#{indent}    output.each_line { |line| output_data.print(line); $stdout.print(line) }\n",
  "#{indent}    raise \"Local deployment script failed with exit status \#{wait_thr.value.exitstatus}\" unless wait_thr.value.success?\n",
  "#{indent}  end\n",
  "#{indent}  receipt = JSON.parse(output_data.string.lines.grep(/\\{/).last || \"{}\")\n",
  "#{indent}else\n"
]

lines.insert(ssh_start_line_idx, *local_exec_code)

rescue_line_idx = lines.find_index.with_index { |l, i| i > ssh_start_line_idx && l.strip.start_with?("rescue") }
abort "Error: rescue keyword not found after Net::SSH.start." unless rescue_line_idx

lines.insert(rescue_line_idx, "#{indent}end\n")

File.write(path, lines.join)
puts "Successfully patched #{path} with precise line-level injection!"