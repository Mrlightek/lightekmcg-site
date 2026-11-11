#!/bin/bash
# fix_server_instances_service_call.sh
# Run this from your Rails application root on macOS.

set -euo pipefail

CONTROLLER="app/controllers/dashboard/server_instances_controller.rb"

echo "Updating server instances controller service invocation..."

# Ensure the controller passes domain: attributes[:domain] explicitly to the provisioning service
cat << 'EOF' > fix_snippet.rb
# Ruby snippet replacement logic
file = "app/controllers/dashboard/server_instances_controller.rb"
content = File.read(file)

# Make sure domain is passed as a keyword argument in the service call
content.gsub!(/Hosting::Provisioner\.call\s*\(([^)]+)\)/) do |match|
  args = $1
  unless args.include?("domain:")
    args = args.strip + ", domain: attributes[:domain]"
  end
  "Hosting::Provisioner.call(#{args})"
end

File.write(file, content)
EOF

ruby fix_snippet.rb
rm fix_snippet.rb

echo "Patch applied successfully!"
git diff "$CONTROLLER"