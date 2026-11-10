#!/bin/bash
# update_site_host_references.sh
# Run this script from the root of your Rails application directory on macOS.

set -euo pipefail

echo "Searching and updating DymondSite site domain references to host..."

# Use find and sed (BSD-compatible for macOS) to replace .find_by(domain: ...), .where(domain: ...), etc.
# targeting app/ and lib/ directories
find app lib -type f \( -name "*.rb" \) -exec sed -i '' \
  's/\bdomain\s*:\s*/host: /g' {} +

echo "Updates applied successfully!"
echo "Verifying changes with git status and diff:"
git status
git diff