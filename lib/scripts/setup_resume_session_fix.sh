#!/bin/bash
set -e

cat > ~/Desktop/Development/dymond_site/app/controllers/dymond_site/application_controller.rb << 'EOF'
module DymondSite
  class ApplicationController < ActionController::Base
    # allow_unauthenticated_access skips require_authentication (no forced
    # login) — but resume_session only ever ran INSIDE require_authentication,
    # so skipping it meant Current.session, and current_user, stayed nil even
    # for a genuinely signed-in visitor. Calling resume_session directly here
    # fixes that: reads the cookie if present, sets nothing if not, never redirects.
    include Authentication
    allow_unauthenticated_access
    before_action :resume_session

    helper_method :current_user

    def current_user
      Current.session&.user
    end

    include DymondSite::SiteContext
    helper DymondSite::RenderingHelper
  end
end
EOF

echo "Done. Next:"
echo "  cd ~/Desktop/Development/dymond_site"
echo "  git add -A && git commit -m 'Actually resume session on public pages, not just skip auth' && git push"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update dymond_site"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
