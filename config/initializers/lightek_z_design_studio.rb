# frozen_string_literal: true
Rails.application.config.to_prepare do
  catalog = LightekDesign::Catalog
  catalog.singleton_class.alias_method(:builtin_designs, :designs) unless catalog.respond_to?(:builtin_designs)
  catalog.singleton_class.prepend(LightekDesign::StudioCatalog) unless catalog.singleton_class < LightekDesign::StudioCatalog
  copies = LightekDesign::WebsiteDesigns.singleton_class
  copies.prepend(LightekDesign::StudioSiteCopies) unless copies < LightekDesign::StudioSiteCopies
  registry = DymondSite::SectionRegistry.singleton_class
  registry.prepend(LightekDesign::StudioSectionRegistry) unless registry < LightekDesign::StudioSectionRegistry
  controller = DymondDash::TemplatesController
  controller.prepend(LightekDesign::StudioTemplateGuard) unless controller < LightekDesign::StudioTemplateGuard
  [DymondSite::PagesController, "LightekWebsiteDeliveryController".safe_constantize].compact.each do |public_controller|
    public_controller.helper(LightekDesign::StudioHelper)
  end
end
