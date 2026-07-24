#!/bin/bash
set -e

echo "Adding Authentication concern to DymondSite::ApplicationController (site-wide, public pages stay public)..."
cat > ~/Desktop/Development/dymond_site/app/controllers/dymond_site/application_controller.rb << 'EOF'
module DymondSite
  class ApplicationController < ActionController::Base
    # Same Authentication concern the host app uses — one auth path, not two.
    # allow_unauthenticated_access (no args) means every action here stays
    # public; current_user just resolves to nil for a signed-out visitor
    # instead of raising, and to the real user when a session exists.
    include Authentication
    allow_unauthenticated_access

    include DymondSite::SiteContext
    helper DymondSite::RenderingHelper
  end
end
EOF

echo "Making the reseller label handle a signed-out visitor gracefully..."
sed -i '' 's|RESELLER: <%= current_user.respond_to?(:full_name) ? current_user.full_name.upcase : current_user.email_address.upcase %> · DISTRIBUTOR TIER|RESELLER: <%= current_user ? (current_user.respond_to?(:full_name) ? current_user.full_name.upcase : current_user.email_address.upcase) : "GUEST" %> · DISTRIBUTOR TIER|' \
  ~/Desktop/Development/dymond_catalog/app/views/dymond_catalog/catalog/index.html.erb

echo ""
echo "Done. Next:"
echo "  cd ~/Desktop/Development/dymond_site"
echo "  git add -A && git commit -m 'Include Authentication concern site-wide, pages stay public' && git push"
echo ""
echo "  cd ~/Desktop/Development/dymond_catalog"
echo "  git add -A && git commit -m 'Handle signed-out visitor in reseller label' && git push"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update dymond_site dymond_catalog"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
