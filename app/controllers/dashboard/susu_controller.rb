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
