# frozen_string_literal: true
class Dashboard::PlatformSettingsController < DymondDash::SettingsController
  before_action :require_platform_operator!
  def update
    @app_config = DymondDash::AppConfig.current || DymondDash::AppConfig.new
    if @app_config.update(settings_params)
      redirect_to dashboard_platform_settings_path, notice: "Dashboard settings saved."
    else
      @panels = safe_panels
      render :index, status: :unprocessable_entity
    end
  end
  private
  def require_platform_operator!
    head :forbidden unless current_user&.role == "super_admin"
  end
end
