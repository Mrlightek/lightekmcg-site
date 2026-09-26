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
