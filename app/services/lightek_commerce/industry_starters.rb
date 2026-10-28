# frozen_string_literal: true
module LightekCommerce
  # Reuses Dymond Site Pages and Sections; industry kits remain editable.
  module IndustryStarters
    INDUSTRIES = {
      "retail" => {name: "Retail & Boutique", heading: "Find something you love", intro: "Shop our latest collection."},
      "beauty" => {name: "Beauty & Wellness", heading: "Your next favorite", intro: "Discover our products and essentials."},
      "food" => {name: "Food & Hospitality", heading: "Made for you", intro: "Browse what is available."},
      "creators" => {name: "Artists & Creators", heading: "Shop the drop", intro: "Support original work."},
      "services" => {name: "Professional Services", heading: "Explore our services", intro: "See what we offer."}
    }.freeze

    def self.install!(site:, industry:)
      definition = INDUSTRIES.fetch(industry.to_s)
      page = StarterPage.create!(site: site)
      section = page.sections.find_by!(kind: "lightek_product_grid")
      section.update!(data: section.data.to_h.merge("heading" => definition[:heading], "intro" => definition[:intro]))
      page
    end
  end
end
