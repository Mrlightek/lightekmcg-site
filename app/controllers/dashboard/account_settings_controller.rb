# frozen_string_literal: true

# Keep personal settings separate from the restricted operator controller tree.
class Dashboard::AccountSettingsController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    response.headers["Cache-Control"] = "no-store, private"
    @settings_operator = current_user.role.in?(%w[admin super_admin])
    render "dashboard/settings_home/index"
  end
end
