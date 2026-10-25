# frozen_string_literal: true
class Dashboard::SettingsHomeController < DymondDash::ApplicationController
  before_action :require_settings_operator!
  private
  def require_settings_operator!
    head :forbidden unless current_user&.role.to_s.in?(%w[admin super_admin])
  end
end
