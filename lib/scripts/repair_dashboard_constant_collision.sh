#!/usr/bin/env bash
set -euo pipefail
cd "${1:-.}"
[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_dashboard_constant_collision_${STAMP}"
mkdir -p "$BACKUP"

for f in config/routes.rb app/controllers/dashboard/infrastructure_controller.rb app/controllers/dashboard/susu_controller.rb; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

cat > app/controllers/dashboard_infrastructure_controller.rb <<'RUBY'
class DashboardInfrastructureController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
    @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)
    @operations = GatekeeperOperation.includes(:gatekeeper_node, :gatekeeper_project).recent_first.limit(20)
    @metrics = Gatekeeper::Metrics.summary
    render "dashboard/infrastructure/index"
  end
end
RUBY

cat > app/controllers/dashboard_susu_controller.rb <<'RUBY'
class DashboardSusuController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @groups = SusuGroup.order(created_at: :desc).limit(20)
    @memberships_count = SusuMembership.count
    @contributions_count = SusuContribution.count
    @cycles_count = SusuCycle.count
    @pending_contributions = SusuContribution.column_names.include?("status") ? SusuContribution.where(status: "pending").count : 0

    @ready = %w[
      susu_groups susu_memberships susu_contributions susu_cycles
      susu_rounds susu_commitments susu_match_preferences
    ].all? { |table| ActiveRecord::Base.connection.data_source_exists?(table) }

    render "dashboard/susu/index"
  end
end
RUBY

rm -f app/controllers/dashboard/infrastructure_controller.rb app/controllers/dashboard/susu_controller.rb
rmdir app/controllers/dashboard 2>/dev/null || true

python3 - config/routes.rb <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
src = path.read_text()

start = src.find("  namespace :dashboard do")
if start < 0:
    raise SystemExit("ERROR: dashboard namespace block not found")

end = src.find("\n  end", start)
if end < 0:
    raise SystemExit("ERROR: dashboard namespace end not found")
end += len("\n  end")

replacement = '''  get "/dashboard/infrastructure",
      to: "dashboard_infrastructure#index",
      as: :dashboard_infrastructure

  get "/dashboard/susu",
      to: "dashboard_susu#index",
      as: :dashboard_susu'''

src = src[:start] + replacement + src[end:]
path.write_text(src)
print("Removed Dashboard namespace collision while preserving /dashboard URLs.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/dashboard_infrastructure_controller.rb
ruby -c app/controllers/dashboard_susu_controller.rb

echo
echo "=== ROUTES ==="
bin/rails routes | grep -E 'dashboard_(infrastructure|susu)'

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
echo "Dashboard ActiveRecord model remains untouched."
echo "/dashboard/infrastructure and /dashboard/susu remain unchanged."
