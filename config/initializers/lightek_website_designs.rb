# frozen_string_literal: true
Rails.application.config.to_prepare do
  LightekDesign::Catalog.register_sections!
  [DymondDash::PagesController, DymondDash::SectionsController, DymondDash::TemplatesController].each do |controller|
    controller.prepend(LightekDesign::SiteEditorScope) unless controller < LightekDesign::SiteEditorScope
  end
  controller = DymondDash::TemplatesController
  controller.prepend(LightekDesign::TemplateCompatibility) unless controller < LightekDesign::TemplateCompatibility
  ["DymondSite::PagesController", "LightekWebsiteDeliveryController"].each do |name|
    controller = name.safe_constantize
    controller.prepend(LightekDesign::PublicWebsite) if controller && !(controller < LightekDesign::PublicWebsite)
  end
end
