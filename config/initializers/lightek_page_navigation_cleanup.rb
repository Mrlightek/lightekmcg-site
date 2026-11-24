# frozen_string_literal: true

Rails.application.config.to_prepare do
  DymondSite::Page.include(LightekDesign::PageNavigationCleanup)
end
