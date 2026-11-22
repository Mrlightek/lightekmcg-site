# frozen_string_literal: true

class Dashboard::NevaehExecutiveController < DymondDash::ApplicationController
  def show
    response.set_header('Cache-Control', 'private, no-store')
    return head :forbidden unless NevaehOs::ExecutiveBrief.available_to?(current_user)

    @sections = NevaehOs::ExecutiveBrief.new(current_user).sections
  end
end
