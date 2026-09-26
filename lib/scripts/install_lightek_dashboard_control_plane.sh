#!/usr/bin/env bash
set -euo pipefail

cd "${1:-.}"
[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/dashboard_control_plane_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  [[ -f "$1" ]] || return 0
  mkdir -p "$BACKUP/$(dirname "$1")"
  cp "$1" "$BACKUP/$1"
}

for f in config/routes.rb \
         app/controllers/gatekeeper/infrastructure_controller.rb \
         app/views/dymond_dash/dashboard/index.html.erb \
         lib/scripts/gatekeeper/deploy_project.sh; do
  backup "$f"
done

mkdir -p app/controllers/dashboard \
         app/views/dashboard/infrastructure \
         app/views/dashboard/susu \
         app/views/dymond_dash/dashboard \
         lib/tasks

python3 - config/routes.rb <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
block = '  # Lightek human control plane\n  namespace :dashboard do\n    get "infrastructure", to: "infrastructure#index", as: :infrastructure\n    get "susu",           to: "susu#index",           as: :susu\n  end\n\n'
if 'get "infrastructure", to: "infrastructure#index"' not in s:
    pos = s.find("mount DymondDash::Engine")
    if pos >= 0:
        start = s.rfind("\n", 0, pos) + 1
        s = s[:start] + block + s[start:]
    else:
        needle = "Rails.application.routes.draw do\n"
        if needle not in s:
            raise SystemExit("ERROR: Rails route draw block not found")
        s = s.replace(needle, needle + block, 1)
    p.write_text(s)
    print("Added dashboard control-plane routes.")
else:
    print("Dashboard control-plane routes already present.")
PY

cat > app/controllers/dashboard/infrastructure_controller.rb <<'RUBY'
module Dashboard
  class InfrastructureController < DymondDash::ApplicationController
    layout "dymond_dash/layouts/dymond_dash"

    def index
      @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
      @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)
      @operations = GatekeeperOperation.includes(:gatekeeper_node, :gatekeeper_project).recent_first.limit(20)
      @metrics = Gatekeeper::Metrics.summary
    end
  end
end
RUBY

cat > app/controllers/dashboard/susu_controller.rb <<'RUBY'
module Dashboard
  class SusuController < DymondDash::ApplicationController
    layout "dymond_dash/layouts/dymond_dash"

    def index
      @groups = SusuGroup.order(created_at: :desc).limit(20)
      @memberships_count = SusuMembership.count
      @contributions_count = SusuContribution.count
      @cycles_count = SusuCycle.count
      @pending_contributions = SusuContribution.column_names.include?("status") ? SusuContribution.where(status: "pending").count : 0
      @ready = %w[susu_groups susu_memberships susu_contributions susu_cycles susu_rounds susu_commitments susu_match_preferences].all? { |table| ActiveRecord::Base.connection.data_source_exists?(table) }
    end
  end
end
RUBY

cat > app/views/dashboard/infrastructure/index.html.erb <<'ERB'
<% content_for :page_title, "Infrastructure" %>
<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Gatekeeper · Operations</div>
  <h2 style="font-size:22px;margin:6px 0 0">Infrastructure Control</h2>
  <p style="color:var(--dd-text-secondary);font-size:13px">Nevaeh decides. Gatekeeper executes. Marlon handles the unknown.</p>
</div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-bottom:18px">
  <% [["Nodes", @nodes.count], ["Projects", @projects.count], ["Operations", @metrics[:operations]], ["Succeeded", @metrics[:succeeded]], ["Failed", @metrics[:failed]], ["Need Intervention", @metrics[:open_support_tickets]]].each do |label, value| %>
    <div class="dd-card" style="padding:18px"><div style="font-size:28px;font-weight:700"><%= value %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= label %></div></div>
  <% end %>
</div>
<div class="dd-card" style="padding:20px;margin-bottom:16px">
  <div style="display:flex;justify-content:space-between;align-items:center"><strong>Marlon Dependency</strong><strong style="font-size:24px;color:var(--dd-accent-primary)"><%= number_to_percentage(@metrics[:marlon_dependency_rate].to_f * 100, precision: 2) %></strong></div>
</div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px">
  <div class="dd-card" style="padding:20px"><h3>Nodes</h3><% @nodes.each do |node| %><div style="padding:10px 0;border-bottom:1px solid var(--dd-border-color)"><strong><%= node.name %></strong> · <%= node.status %><br><small style="color:var(--dd-text-secondary)"><%= node.display_host %></small></div><% end %></div>
  <div class="dd-card" style="padding:20px"><h3>Projects</h3><% @projects.each do |project| %><div style="padding:10px 0;border-bottom:1px solid var(--dd-border-color)"><strong><%= project.name %></strong> · <%= project.status %><br><small style="color:var(--dd-text-secondary)"><%= project.domain %><% if project.deployed_sha.present? %> · <%= project.deployed_sha.first(8) %><% end %></small></div><% end %></div>
</div>
<div class="dd-card" style="padding:20px;margin-top:16px"><h3>Recent Automation</h3><% if @operations.any? %><% @operations.each do |op| %><div style="padding:10px 0;border-bottom:1px solid var(--dd-border-color);font-size:13px"><strong><%= op.capability.humanize %></strong> · <%= op.status %> · <span style="color:var(--dd-text-secondary)"><%= op.requested_by %></span></div><% end %><% else %><p style="color:var(--dd-text-secondary)">No Gatekeeper operations yet.</p><% end %></div>
ERB

cat > app/views/dashboard/susu/index.html.erb <<'ERB'
<% content_for :page_title, "Susu" %>
<div style="margin-bottom:20px"><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Financial Services · Susu</div><h2 style="font-size:22px;margin:6px 0 0">Susu Operations</h2></div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-bottom:18px">
  <% [["Production", (@ready ? "READY" : "CHECK")], ["Groups", SusuGroup.count], ["Memberships", @memberships_count], ["Cycles", @cycles_count], ["Contributions", @contributions_count], ["Pending", @pending_contributions]].each do |label, value| %>
    <div class="dd-card" style="padding:18px"><div style="font-size:25px;font-weight:700"><%= value %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= label %></div></div>
  <% end %>
</div>
<div class="dd-card" style="padding:20px"><div style="display:flex;justify-content:space-between;align-items:center"><h3>Recent Groups</h3><%= link_to "Open Susu →", main_app.susu_groups_path, class: "dd-topbar-btn dd-btn-primary" %></div><% if @groups.any? %><% @groups.each do |group| %><div style="padding:10px 0;border-bottom:1px solid var(--dd-border-color)"><strong><%= group.respond_to?(:name) ? group.name : "Susu ##{group.id}" %></strong></div><% end %><% else %><p style="padding:24px 0;text-align:center;color:var(--dd-text-secondary)">Susu is production-ready. No groups have been created yet.</p><% end %></div>
ERB

cat > app/views/dymond_dash/dashboard/index.html.erb <<'ERB'
<% content_for :page_title, "Dashboard" %>
<%
  metrics = defined?(Gatekeeper::Metrics) ? Gatekeeper::Metrics.summary : { operations: 0, succeeded: 0, failed: 0, open_support_tickets: 0, human_interventions: 0, marlon_dependency_rate: 0.0 }
  node_count = defined?(GatekeeperNode) ? GatekeeperNode.count : 0
  healthy_nodes = defined?(GatekeeperNode) ? GatekeeperNode.where(status: "healthy").count : 0
  project_count = defined?(GatekeeperProject) ? GatekeeperProject.count : 0
  healthy_projects = defined?(GatekeeperProject) ? GatekeeperProject.where(status: "healthy").count : 0
  susu_ready = defined?(SusuGroup) && %w[susu_groups susu_memberships susu_contributions susu_cycles susu_rounds susu_commitments susu_match_preferences].all? { |t| ActiveRecord::Base.connection.data_source_exists?(t) }
  susu_groups = defined?(SusuGroup) ? SusuGroup.count : 0
  pending = defined?(SusuContribution) && SusuContribution.column_names.include?("status") ? SusuContribution.where(status: "pending").count : 0
%>
<div style="margin-bottom:20px"><div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Nevaeh · Organizational Overview</div><h2 style="font-size:24px;margin:6px 0 0">LIGHTEK TODAY</h2><p style="color:var(--dd-text-secondary);font-size:13px"><%= Date.current.strftime("%A, %B %-d %Y") %> · What needs your attention, and what does not.</p></div>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px">
  <%= link_to main_app.dashboard_infrastructure_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %><small style="color:var(--dd-text-muted)">INFRASTRUCTURE</small><div style="font-size:28px;font-weight:700;margin-top:8px"><%= healthy_nodes %>/<%= node_count %></div><div style="color:var(--dd-text-secondary);font-size:12px">nodes healthy · <%= healthy_projects %>/<%= project_count %> projects healthy</div><% end %>
  <%= link_to main_app.dashboard_susu_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %><small style="color:var(--dd-text-muted)">SUSU</small><div style="font-size:28px;font-weight:700;margin-top:8px"><%= susu_ready ? "READY" : "CHECK" %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= susu_groups %> groups · <%= pending %> pending contributions</div><% end %>
  <div class="dd-card" style="padding:20px"><small style="color:var(--dd-text-muted)">AUTOMATION</small><div style="font-size:28px;font-weight:700;margin-top:8px"><%= metrics[:operations] %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= metrics[:succeeded] %> succeeded · <%= metrics[:failed] %> failed · <%= metrics[:open_support_tickets] %> need intervention</div></div>
  <div class="dd-card" style="padding:20px"><small style="color:var(--dd-text-muted)">MARLON DEPENDENCY</small><div style="font-size:28px;font-weight:700;margin-top:8px"><%= number_to_percentage(metrics[:marlon_dependency_rate].to_f * 100, precision: 2) %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= metrics[:human_interventions] %> human intervention(s)</div></div>
</div>
<div class="dd-card" style="padding:20px;margin-top:16px"><% if metrics[:open_support_tickets].to_i.zero? %><strong>Nothing requires Marlon right now.</strong><div style="color:var(--dd-text-secondary);font-size:12px;margin-top:4px">Gatekeeper has no open operational escalations.</div><% else %><strong><%= metrics[:open_support_tickets] %> item(s) require intervention.</strong><div style="color:var(--dd-text-secondary);font-size:12px;margin-top:4px">Open Infrastructure for Gatekeeper diagnostics.</div><% end %></div>
ERB

cat > app/controllers/gatekeeper/infrastructure_controller.rb <<'RUBY'
module Gatekeeper
  class InfrastructureController < ApplicationController
    def index
      redirect_to main_app.dashboard_infrastructure_path, status: :see_other
    end
  end
end
RUBY

cat > lib/tasks/gatekeeper_dashboard_nav.rake <<'RUBY'
namespace :gatekeeper do
  desc "Register Infrastructure and Susu in DymondDash navigation"
  task dashboard_nav: :environment do
    operations = DymondDash::NavSection.find_or_initialize_by(slug: "operations")
    operations.label = "Operations"
    operations.position = 80 if operations.position.to_i.zero?
    operations.save!

    services = DymondDash::NavSection.find_or_initialize_by(slug: "services")
    services.label = "Services"
    services.position = 60 if services.position.to_i.zero?
    services.save!

    infrastructure = DymondDash::NavItem.find_or_initialize_by(section: operations, label: "Infrastructure")
    infrastructure.assign_attributes(icon: "server", path_helper: "dashboard_infrastructure_path", position: 10, visible: true, feature_slug: nil)
    infrastructure.save!

    susu = DymondDash::NavItem.find_or_initialize_by(section: services, label: "Susu")
    susu.assign_attributes(icon: "users-group", path_helper: "dashboard_susu_path", position: 90, visible: true, feature_slug: nil)
    susu.save!

    puts "DymondDash navigation registered:"
    puts "  Operations -> Infrastructure"
    puts "  Services   -> Susu"
  end
end
RUBY

python3 - lib/scripts/gatekeeper/deploy_project.sh <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print("No Gatekeeper deploy script found; skipping automatic nav hook.")
    sys.exit(0)
s = p.read_text()
if "gatekeeper:dashboard_nav" in s:
    print("Deploy script already runs dashboard_nav.")
    sys.exit(0)
needle = 'run_rails "bundle exec rails db:migrate"'
if needle in s:
    s = s.replace(needle, needle + '\n\necho "[nav] Register dashboard control-plane navigation"\nrun_rails "bundle exec rails gatekeeper:dashboard_nav"', 1)
    p.write_text(s)
    print("Added dashboard nav registration to deploy script.")
else:
    print("db:migrate marker not found; run gatekeeper:dashboard_nav once manually.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/dashboard/infrastructure_controller.rb
ruby -c app/controllers/dashboard/susu_controller.rb
ruby -c app/controllers/gatekeeper/infrastructure_controller.rb
ruby -c lib/tasks/gatekeeper_dashboard_nav.rake

echo
echo "=== SHELL SYNTAX ==="
bash -n lib/scripts/gatekeeper/deploy_project.sh

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "Installed Lightek dashboard control plane."
echo "Backup: $BACKUP"
echo
echo "Next:"
echo "  bin/rails gatekeeper:dashboard_nav"
echo "  bin/rails routes | grep -E 'dashboard_(infrastructure|susu)'"
echo "  bin/rails zeitwerk:check"
echo "  git add -A"
echo '  git commit -m "Integrate Gatekeeper and Susu into DymondDash"'
echo "  git push origin main"
