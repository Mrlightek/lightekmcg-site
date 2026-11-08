# frozen_string_literal: true
class Dashboard::NevaehNavigationController < ::DymondDash::ApplicationController
  def update
    preference = NevaehWorkspacePreference.find_or_initialize_by(user: current_user)
    raw = params.require(:navigation_json).to_s
    raise ArgumentError, "Sidebar definition is too large" if raw.bytesize > 50000
    preference.navigation = NevaehIntelligences::WorkspaceNavigation.normalize(JSON.parse(raw))
    preference.save!
    redirect_back fallback_location: main_app.dashboard_settings_home_path, notice: "Your sidebar is saved."
  rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: main_app.dashboard_settings_home_path, alert: error.message
  end
end
