Rails.application.config.to_prepare do
  DymondDash::ApplicationController.helper(AgencyBrandingHelper)
end
