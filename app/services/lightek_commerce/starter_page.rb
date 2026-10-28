# frozen_string_literal: true
module LightekCommerce
  # Creates an editable draft on a selected customer-owned Dymond Site.
  # It never changes the public home page or publishes without merchant action.
  class StarterPage
    def self.create!(site:)
      site.with_lock do
        existing = site.manifest.to_h["lightek_commerce_starter_page_id"]
        return site.pages.find(existing) if existing && site.pages.exists?(id: existing)
        base = "shop"
        slug = base
        sequence = 2
        while site.pages.exists?(slug: slug)
          slug = "#{base}-#{sequence}"
          sequence += 1
        end
        page = site.pages.create!(title: "Shop", slug: slug, published: false,
          position: site.pages.maximum(:position).to_i + 1)
        definition = LightekDesign::CommerceSections.definitions.first
        page.sections.create!(kind: definition.fetch("kind"), position: 0, data: definition.fetch("data").deep_dup)
        site.update!(manifest: site.manifest.to_h.merge("lightek_commerce_starter_page_id" => page.id))
        page
      end
    end
  end
end
