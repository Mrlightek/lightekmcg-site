#!/usr/bin/env bash
set -euo pipefail

cd "${1:-.}"
[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_dashboard_nested_controllers_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

backup config/routes.rb
backup app/controllers/dashboard_infrastructure_controller.rb
backup app/controllers/dashboard_susu_controller.rb
backup app/controllers/dashboard/infrastructure_controller.rb
backup app/controllers/dashboard/susu_controller.rb

mkdir -p app/controllers/dashboard

cat > app/controllers/dashboard/infrastructure_controller.rb <<'RUBY'
class Dashboard::InfrastructureController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
    @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)
    @operations = GatekeeperOperation
      .includes(:gatekeeper_node, :gatekeeper_project)
      .recent_first
      .limit(20)
    @metrics = Gatekeeper::Metrics.summary

    render "dashboard/infrastructure/index"
  end
end
RUBY

cat > app/controllers/dashboard/susu_controller.rb <<'RUBY'
class Dashboard::SusuController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @groups = SusuGroup.order(created_at: :desc).limit(20)
    @memberships_count = SusuMembership.count
    @contributions_count = SusuContribution.count
    @cycles_count = SusuCycle.count

    @pending_contributions =
      if SusuContribution.column_names.include?("status")
        SusuContribution.where(status: "pending").count
      else
        0
      end

    @ready = %w[
      susu_groups
      susu_memberships
      susu_contributions
      susu_cycles
      susu_rounds
      susu_commitments
      susu_match_preferences
    ].all? { |table| ActiveRecord::Base.connection.data_source_exists?(table) }

    render "dashboard/susu/index"
  end
end
RUBY

# Remove the temporary top-level controller files created by the previous repair.
rm -f app/controllers/dashboard_infrastructure_controller.rb
rm -f app/controllers/dashboard_susu_controller.rb

echo "=== CONTROLLER FILES ==="
find app/controllers -maxdepth 2 -type f \
  | grep -E 'dashboard(_|/)(infrastructure|susu)_controller\.rb' \
  | sort || true

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/dashboard/infrastructure_controller.rb
ruby -c app/controllers/dashboard/susu_controller.rb

echo
echo "=== ROUTE DEFINITIONS AROUND DASHBOARD ==="
grep -n -A12 -B4 -E 'namespace :dashboard|dashboard/infrastructure|dashboard/susu' config/routes.rb || true

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== RESOLVED ROUTES ==="
bin/rails routes | grep -E 'dashboard_(infrastructure|susu)' || true

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
echo
echo "Existing Dashboard ActiveRecord model was preserved."
echo "Zeitwerk now gets exactly the constants it expects from:"
echo "  app/controllers/dashboard/infrastructure_controller.rb"
echo "  app/controllers/dashboard/susu_controller.rb"
