class Dashboard::CommerceBaseController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action { head :forbidden unless current_user&.role.in?(%w[super_admin admin white_label client]) }
end
