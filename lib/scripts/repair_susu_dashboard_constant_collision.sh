#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="app/controllers/dashboard/susu_controller.rb"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_susu_dashboard_constant_${STAMP}"
mkdir -p "$BACKUP/app/controllers/dashboard"
cp "$FILE" "$BACKUP/$FILE"

cat > "$FILE" <<'RUBY'
class Dashboard::SusuController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @ready = %w[
      susu_groups
      susu_memberships
      susu_contributions
      susu_cycles
      susu_rounds
      susu_commitments
      susu_match_preferences
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
      @pending_contributions = SusuContribution.where(
        user_id: current_user.id,
        status: "pending"
      ).count

      @funded_rounds = SusuRound
        .joins(:susu_cycle)
        .where(
          susu_cycles: { susu_group_id: group_ids },
          status: "funded"
        )
        .count

      @processing_rounds = SusuRound
        .joins(:susu_cycle)
        .where(
          susu_cycles: { susu_group_id: group_ids },
          status: "processing"
        )
        .count
    end

    render "dashboard/susu/index"
  end
end
RUBY

echo "=== CONTROLLER HEADER ==="
sed -n '1,12p' "$FILE"

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$FILE"

echo
echo "=== DASHBOARD CONSTANT CHECK ==="
bin/rails runner '
puts "Dashboard class: #{Dashboard.class}"
puts "Dashboard AR model: #{Dashboard < ApplicationRecord}"
puts "Susu controller: #{Dashboard::SusuController.name}"
puts "Controller parent: #{Dashboard::SusuController.superclass.name}"
'

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== ROUTE RESOLUTION ==="
bin/rails routes | grep -E 'dashboard_susu|dashboard_susu_payout_account|request_payout_susu_group'

echo
echo "=== CLIENT DATA-SCOPE CHECK ==="
bin/rails runner '
client = User.where(role: "client").first

if client
  organized = SusuGroup.where(organizer: client)
  member = SusuGroup.joins(:susu_memberships)
                    .where(susu_memberships: { user_id: client.id })

  visible = SusuGroup
    .where(id: organized.select(:id))
    .or(SusuGroup.where(id: member.select(:id)))
    .distinct

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
echo "=== PAYOUT VIEW MARKER ==="
grep -n "SUSU PAYOUT CONTROL" app/views/susu_groups/show.html.erb || {
  echo "ERROR: payout UI marker missing" >&2
  exit 1
}

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
echo
echo "The existing Dashboard ActiveRecord model was preserved."
echo "Dashboard::SusuController now reopens the Dashboard class instead of declaring Dashboard as a module."
