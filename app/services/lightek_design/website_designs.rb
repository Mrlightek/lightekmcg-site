# frozen_string_literal: true
module LightekDesign
  class WebsiteDesigns
    FONT_KEYS = %w[font_sans font_heading font_mono].freeze

    def self.template_for!(site:, design:)
      definition = Catalog.fetch(design)
      key = "lightek_site_#{site.id}_#{design}"
      template = DymondSite::SiteTemplate.find_or_initialize_by(key: key)
      if template.new_record?
        template.assign_attributes(name: "#{definition.fetch('name')} · website #{site.id}", preset: false,
          description: definition.fetch("description"), settings: {
            "lightek_design" => design.to_s, "lightek_site_id" => site.id,
            "tokens" => definition.fetch("tokens").merge(definition.fetch("fonts")),
            "nav_layout" => "left", "footer_style" => "columns"
          })
        template.save!
      end
      raise ActiveRecord::RecordNotFound unless template.settings["lightek_site_id"].to_s == site.id.to_s
      template
    end

    def self.apply!(site:, design:)
      site.with_lock { site.update!(active_template: template_for!(site: site, design: design)) }
      site
    end

    # Site row lock serializes both import and template creation. A stored page ID
    # protects edited/renamed/published starter pages from later imports.
    def self.import!(site:, design:)
      definition = Catalog.fetch(design)
      site.with_lock do
        manifest = site.manifest.deep_dup
        imports = manifest.fetch("lightek_design_imports", {})
        saved_id = imports[design.to_s]
        existing = site.pages.find_by(id: saved_id) if saved_id
        return existing if existing
        base = "#{design}-starter"
        slug = base
        suffix = 2
        while site.pages.exists?(slug: slug)
          slug = "#{base}-#{suffix}"
          suffix += 1
        end
        page = site.pages.create!(title: "#{definition.fetch('name')} starter", slug: slug,
          published: false, position: site.pages.maximum(:position).to_i + 1)
        definition.fetch("sections").each_with_index do |entry, position|
          page.sections.create!(kind: entry.fetch("kind"), position: position,
            data: entry.fetch("data").deep_dup)
        end
        imports[design.to_s] = page.id
        manifest["lightek_design_imports"] = imports
        site.update!(manifest: manifest)
        page
      end
    end

    def self.save_fonts!(site:, values:)
      supplied = values.slice(*FONT_KEYS).transform_values { |value| value.to_s.strip }
      supplied.each_value do |value|
        raise ArgumentError, "Enter a font family name or a valid font stack." unless value.blank? || Fonts.valid_stack?(value)
      end
      site.with_lock do
        design = Catalog.design_for(site)
        raise ArgumentError, "Choose a design first." unless Catalog.designs.key?(design)
        template = template_for!(site: site, design: design)
        settings = template.settings.deep_dup
        settings["tokens"] = settings.fetch("tokens", {}).merge(supplied)
        template.update!(settings: settings)
        site.update!(active_template: template) unless site.active_template_id == template.id
      end
      site
    end
  end
end
