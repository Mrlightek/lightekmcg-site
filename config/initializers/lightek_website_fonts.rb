# frozen_string_literal: true
Rails.application.config.to_prepare do
  if defined?(DymondSite::PagesController)
    controller = DymondSite::PagesController
    controller.include(LightekDesign::WebsiteFonts) unless controller < LightekDesign::WebsiteFonts
  end
  if defined?(LightekWebsiteDeliveryController)
    controller = LightekWebsiteDeliveryController
    controller.include(LightekDesign::WebsiteFonts) unless controller < LightekDesign::WebsiteFonts
  end
  if defined?(DymondSite::SiteTemplate)
    model = DymondSite::SiteTemplate
    unless model.method_defined?(:lightek_validate_font_values)
      model.class_eval do
        validate :lightek_validate_font_values
        def lightek_validate_font_values
          tokens.values_at("font_sans", "font_heading", "font_mono").each do |value|
            next if value.blank? || LightekDesign::Fonts.valid_stack?(value)
            errors.add(:base, "Enter font family names, such as Inter or Source Serif 4.")
          end
        end
      end
    end
  end
end
