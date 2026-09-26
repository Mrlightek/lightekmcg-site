#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_customer_dashboard_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in \
  app/controllers/dashboard/susu_controller.rb \
  app/views/dashboard/susu/index.html.erb \
  app/views/dymond_dash/dashboard/index.html.erb \
  app/views/susu_groups/show.html.erb
do
  backup "$f"
done

cat > app/controllers/dashboard/susu_controller.rb <<'RUBY'
module Dashboard
  class SusuController < DymondDash::ApplicationController
    layout "dymond_dash/layouts/dymond_dash"

    def index
      @ready = %w[
        susu_groups susu_memberships susu_contributions
        susu_cycles susu_rounds susu_commitments susu_match_preferences
      ].all? { |table| ActiveRecord::Base.connection.data_source_exists?(table) }

      if current_user.employee? || current_user.admin?
        @groups = SusuGroup.order(created_at: :desc).limit(20)
        @memberships_count = SusuMembership.count
        @contributions_count = SusuContribution.count
        @cycles_count = SusuCycle.count
        @pending_contributions = SusuContribution.where(status: "pending").count
        @funded_rounds = SusuRound.where(status: "funded").count
        @processing_rounds = SusuRound.where(status: "processing").count
      else
        organized = SusuGroup.where(organizer: current_user)
        member = SusuGroup.joins(:susu_memberships)
                          .where(susu_memberships: { user_id: current_user.id })

        @groups = SusuGroup.where(id: organized.select(:id))
                           .or(SusuGroup.where(id: member.select(:id)))
                           .distinct
                           .order(created_at: :desc)
                           .limit(20)

        group_ids = @groups.map(&:id)
        @memberships_count = SusuMembership.where(susu_group_id: group_ids).count
        @contributions_count = SusuContribution.where(user_id: current_user.id).count
        @cycles_count = SusuCycle.where(susu_group_id: group_ids).count
        @pending_contributions = SusuContribution.where(user_id: current_user.id, status: "pending").count
        @funded_rounds = SusuRound.joins(:susu_cycle)
                                 .where(susu_cycles: { susu_group_id: group_ids }, status: "funded")
                                 .count
        @processing_rounds = SusuRound.joins(:susu_cycle)
                                     .where(susu_cycles: { susu_group_id: group_ids }, status: "processing")
                                     .count
      end
    end
  end
end
RUBY

cat > app/views/dashboard/susu/index.html.erb <<'ERB'
<% content_for :page_title, "Susu" %>

<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Financial Services · Susu</div>
  <h2 style="font-size:22px;margin:6px 0 0">Susu</h2>
  <p style="color:var(--dd-text-secondary);font-size:13px">
    <% if current_user.employee? || current_user.admin? %>
      Customer circles, contributions and payout readiness.
    <% else %>
      Your circles, contributions and payout setup.
    <% end %>
  </p>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-bottom:18px">
  <% [
    ["Status", (@ready ? "READY" : "CHECK")],
    ["My Groups", @groups.count],
    ["Memberships", @memberships_count],
    ["Contributions", @contributions_count],
    ["Pending", @pending_contributions],
    ["Funded Rounds", @funded_rounds]
  ].each do |label, value| %>
    <div class="dd-card" style="padding:18px">
      <div style="font-size:25px;font-weight:700"><%= value %></div>
      <div style="color:var(--dd-text-secondary);font-size:12px"><%= label %></div>
    </div>
  <% end %>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px">
  <div class="dd-card" style="padding:20px">
    <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap">
      <div>
        <h3 style="margin:0">My Susu</h3>
        <p style="margin:5px 0 0;color:var(--dd-text-secondary);font-size:12px">Create and manage your savings circles.</p>
      </div>
      <%= link_to "Open Susu →", main_app.susu_groups_path, class: "dd-topbar-btn dd-btn-primary" %>
    </div>

    <% if @groups.any? %>
      <% @groups.each do |group| %>
        <div style="padding:12px 0;border-bottom:1px solid var(--dd-border-color)">
          <%= link_to main_app.susu_group_path(group), style: "text-decoration:none;color:inherit" do %>
            <strong><%= group.name %></strong>
            <div style="color:var(--dd-text-secondary);font-size:12px">
              <%= group.status.to_s.humanize %> · <%= number_to_currency(group.contribution_amount) %> contribution
            </div>
          <% end %>
        </div>
      <% end %>
    <% else %>
      <p style="padding:24px 0;text-align:center;color:var(--dd-text-secondary)">You do not have a Susu circle yet.</p>
      <div style="text-align:center">
        <%= link_to "Create your first Susu", main_app.new_susu_group_path, class: "dd-topbar-btn dd-btn-primary" %>
      </div>
    <% end %>
  </div>

  <div class="dd-card" style="padding:20px">
    <h3 style="margin-top:0">Payout Account</h3>

    <% if current_user.stripe_connect_ready? %>
      <div style="font-size:28px;font-weight:700;color:var(--dd-accent-primary)">READY</div>
      <p style="color:var(--dd-text-secondary);font-size:13px">Your Stripe connected account is enabled to receive Susu payouts.</p>
      <%= link_to "View payout account", main_app.dashboard_susu_payout_account_path, class: "dd-topbar-btn dd-btn-primary" %>
    <% elsif current_user.stripe_connect_account_id.present? %>
      <div style="font-size:28px;font-weight:700">SETUP</div>
      <p style="color:var(--dd-text-secondary);font-size:13px">Finish Stripe onboarding before a funded round can be sent to you.</p>
      <%= link_to "Continue payout setup", main_app.dashboard_susu_payout_account_path, class: "dd-topbar-btn dd-btn-primary" %>
    <% else %>
      <div style="font-size:28px;font-weight:700">NOT SET</div>
      <p style="color:var(--dd-text-secondary);font-size:13px">Connect a payout destination before your scheduled payout round.</p>
      <%= link_to "Set up payouts", main_app.dashboard_susu_payout_account_path, class: "dd-topbar-btn dd-btn-primary" %>
    <% end %>

    <% if @processing_rounds.to_i > 0 %>
      <div style="margin-top:18px;padding-top:14px;border-top:1px solid var(--dd-border-color);font-size:13px">
        <strong><%= @processing_rounds %></strong> payout round(s) currently processing.
      </div>
    <% end %>
  </div>
</div>
ERB

python3 <<'PY'
from pathlib import Path

path = Path("app/views/susu_groups/show.html.erb")
src = path.read_text()

if "<!-- SUSU PAYOUT CONTROL -->" not in src:
    panel = r'''
<!-- SUSU PAYOUT CONTROL -->
<% round = @susu_group.current_round_record %>
<% if round %>
  <section class="susu-card" style="margin-top:20px">
    <div class="susu-eyebrow">CURRENT ROUND PAYOUT</div>
    <h2>Round <%= round.number %> · <%= round.status.humanize %></h2>
    <p>Recipient: <strong><%= round.recipient.respond_to?(:full_name) ? round.recipient.full_name : round.recipient.email_address %></strong></p>
    <p>
      Settled:
      <strong><%= number_to_currency(round.collected_amount) %></strong>
      of
      <strong><%= number_to_currency(round.expected_pot) %></strong>
    </p>

    <% if round.recipient == current_user && !current_user.stripe_connect_ready? %>
      <%= link_to "Set up my payout account",
                  dashboard_susu_payout_account_path,
                  class: "susu-button susu-button-primary" %>
    <% end %>

    <% if @susu_group.organizer?(current_user) && round.status == "funded" %>
      <% if round.recipient.stripe_connect_ready? %>
        <%= button_to "Send funded round payout",
                      request_payout_susu_group_path(@susu_group),
                      method: :post,
                      class: "susu-button susu-button-primary",
                      data: { turbo_confirm: "Send this funded Susu round to the scheduled recipient?" } %>
      <% else %>
        <p class="susu-muted">The scheduled recipient must finish payout setup before this round can be sent.</p>
      <% end %>
    <% end %>

    <% if round.dymond_bank_payout %>
      <p class="susu-muted">
        Dymond payout #<%= round.dymond_bank_payout.id %> ·
        <%= round.dymond_bank_payout.status.humanize %>
      </p>
    <% end %>
  </section>
<% end %>
'''
    path.write_text(src.rstrip() + "\n\n" + panel + "\n")
    print("Added Susu payout control to group page.")
else:
    print("Susu payout control already present.")
PY

cat > app/views/dymond_dash/dashboard/index.html.erb <<'ERB'
<% content_for :page_title, "Dashboard" %>

<% if current_user.client? || current_user.contractor? %>
  <%
    if defined?(SusuGroup) && current_user.can_access_feature?(:susu)
      organized = SusuGroup.where(organizer: current_user)
      member = SusuGroup.joins(:susu_memberships).where(susu_memberships: { user_id: current_user.id })
      my_groups = SusuGroup.where(id: organized.select(:id))
                           .or(SusuGroup.where(id: member.select(:id)))
                           .distinct
    else
      my_groups = SusuGroup.none
    end
  %>

  <div style="margin-bottom:20px">
    <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Your Lightek Services</div>
    <h2 style="font-size:24px;margin:6px 0 0">Welcome, <%= current_user.first_name %></h2>
    <p style="color:var(--dd-text-secondary);font-size:13px">Everything you currently have access to is here.</p>
  </div>

  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px">
    <% if current_user.can_access_feature?(:susu) %>
      <%= link_to main_app.dashboard_susu_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %>
        <small style="color:var(--dd-text-muted)">SUSU</small>
        <div style="font-size:28px;font-weight:700;margin-top:8px"><%= my_groups.count %></div>
        <div style="color:var(--dd-text-secondary);font-size:12px">circle(s) available to you</div>
      <% end %>

      <%= link_to main_app.dashboard_susu_payout_account_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %>
        <small style="color:var(--dd-text-muted)">PAYOUT ACCOUNT</small>
        <div style="font-size:28px;font-weight:700;margin-top:8px"><%= current_user.stripe_connect_ready? ? "READY" : "SETUP" %></div>
        <div style="color:var(--dd-text-secondary);font-size:12px">
          <%= current_user.stripe_connect_ready? ? "ready to receive Susu payouts" : "complete payout setup before your payout round" %>
        </div>
      <% end %>
    <% end %>
  </div>

<% else %>
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

  <div style="margin-bottom:20px">
    <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Nevaeh · Organizational Overview</div>
    <h2 style="font-size:24px;margin:6px 0 0">LIGHTEK TODAY</h2>
    <p style="color:var(--dd-text-secondary);font-size:13px"><%= Date.current.strftime("%A, %B %-d %Y") %> · What needs your attention, and what does not.</p>
  </div>

  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px">
    <%= link_to main_app.dashboard_infrastructure_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %>
      <small style="color:var(--dd-text-muted)">INFRASTRUCTURE</small>
      <div style="font-size:28px;font-weight:700;margin-top:8px"><%= healthy_nodes %>/<%= node_count %></div>
      <div style="color:var(--dd-text-secondary);font-size:12px">nodes healthy · <%= healthy_projects %>/<%= project_count %> projects healthy</div>
    <% end %>

    <%= link_to main_app.dashboard_susu_path, class: "dd-card", style: "display:block;padding:20px;text-decoration:none;color:inherit" do %>
      <small style="color:var(--dd-text-muted)">SUSU</small>
      <div style="font-size:28px;font-weight:700;margin-top:8px"><%= susu_ready ? "READY" : "CHECK" %></div>
      <div style="color:var(--dd-text-secondary);font-size:12px"><%= susu_groups %> groups · <%= pending %> pending contributions</div>
    <% end %>

    <div class="dd-card" style="padding:20px">
      <small style="color:var(--dd-text-muted)">AUTOMATION</small>
      <div style="font-size:28px;font-weight:700;margin-top:8px"><%= metrics[:operations] %></div>
      <div style="color:var(--dd-text-secondary);font-size:12px"><%= metrics[:succeeded] %> succeeded · <%= metrics[:failed] %> failed · <%= metrics[:open_support_tickets] %> need intervention</div>
    </div>

    <div class="dd-card" style="padding:20px">
      <small style="color:var(--dd-text-muted)">MARLON DEPENDENCY</small>
      <div style="font-size:28px;font-weight:700;margin-top:8px"><%= number_to_percentage(metrics[:marlon_dependency_rate].to_f * 100, precision: 2) %></div>
      <div style="color:var(--dd-text-secondary);font-size:12px"><%= metrics[:human_interventions] %> human intervention(s)</div>
    </div>
  </div>

  <div class="dd-card" style="padding:20px;margin-top:16px">
    <% if metrics[:open_support_tickets].to_i.zero? %>
      <strong>Nothing requires Marlon right now.</strong>
      <div style="color:var(--dd-text-secondary);font-size:12px;margin-top:4px">Gatekeeper has no open operational escalations.</div>
    <% else %>
      <strong><%= metrics[:open_support_tickets] %> item(s) require intervention.</strong>
      <div style="color:var(--dd-text-secondary);font-size:12px;margin-top:4px">Open Infrastructure for Gatekeeper diagnostics.</div>
    <% end %>
  </div>
<% end %>
ERB

echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/dashboard/susu_controller.rb

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== CLIENT DATA-SCOPE CHECK ==="
bin/rails runner '
client = User.where(role: "client").first
if client
  organized = SusuGroup.where(organizer: client)
  member = SusuGroup.joins(:susu_memberships).where(susu_memberships: { user_id: client.id })
  visible = SusuGroup.where(id: organized.select(:id)).or(SusuGroup.where(id: member.select(:id))).distinct
  puts "client=#{client.id}"
  puts "susu_access=#{client.can_access_feature?(:susu)}"
  puts "infrastructure_access=#{client.can_access_feature?(:gatekeeper_infrastructure)}"
  puts "visible_susu_groups=#{visible.count}"
  puts "all_susu_groups=#{SusuGroup.count}"
else
  puts "No client user exists."
end
'

echo
echo "=== PAYOUT UI ROUTES ==="
bin/rails routes | grep -E 'dashboard_susu_payout_account|request_payout_susu_group'

echo
echo "=== PAYOUT VIEW MARKER ==="
grep -n "SUSU PAYOUT CONTROL" app/views/susu_groups/show.html.erb

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "DONE"
echo "Backup: $BACKUP"
