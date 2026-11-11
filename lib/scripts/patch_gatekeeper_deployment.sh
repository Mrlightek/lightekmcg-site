#!/bin/bash
# patch_gatekeeper_deployment.sh
# Run this script from the root of your Rails application directory on macOS.

set -euo pipefail

TARGET_FILE="app/services/gatekeeper/website_deployment.rb"

if [ ! -f "$TARGET_FILE" ]; then
  echo "Error: Could not find $TARGET_FILE. Please run this script from your Rails root directory."
  exit 1
fi

echo "Patching $TARGET_FILE..."

# Backup original file before modification
cp "$TARGET_FILE" "${TARGET_FILE}.bak"

# Use macOS sed (BSD) to update the restriction check on line 139
sed -i '' \
  's/raise Invalid, "Only remote root SSH targets are supported by this installation path" if @node\.local? || @node\.ssh_user != "root"/raise Invalid, "Only remote root SSH targets are supported by this installation path" if !@node.local? \&\& @node.ssh_user != "root"/' \
  "$TARGET_FILE"

echo "Patch applied successfully!"
echo "Verifying changes with git diff:"
git diff "$TARGET_FILE"