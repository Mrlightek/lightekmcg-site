#!/bin/bash
# fix_server_instances_controller.sh
# Run this script from the root of your Rails application directory on macOS.

set -euo pipefail

CONTROLLER="app/controllers/dashboard/server_instances_controller.rb"

echo "Checking and patching $CONTROLLER..."

if [ ! -f "$CONTROLLER" ]; then
  echo "Error: $CONTROLLER not found at $CONTROLLER!"
  exit 1
fi

# Use Ruby to cleanly and safely update the strong parameters and keyword arguments
ruby -pi -e '
  content = $_
  # Ensure permitted params include domain and gatekeeper_project_id
  content.gsub!(/permit\([^)]+\)/, "permit(:name, :domain, :gatekeeper_project_id, :owner_id)")
  $_ = content
' "$CONTROLLER"

echo "Controller patch applied successfully!"
echo "Showing git diff for review:"
git diff "$CONTROLLER"