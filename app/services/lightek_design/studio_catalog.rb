# frozen_string_literal: true
module LightekDesign
  module StudioCatalog
    def designs = builtin_designs.merge(StudioContext.designs)
    def fetch(key)
      builtin_designs.key?(key.to_s) ? builtin_designs.fetch(key.to_s) : StudioContext.resolve(key.to_s)
    end
    def active?(site)
      key = design_for(site)
      key.present? && fetch(key).present?
    rescue KeyError
      false
    end
    def section_definition(kind)
      if (match = kind.to_s.match(/\Ald_(\d+)_v(\d+)_/))
        fetch("ld_release_#{match[1]}_v#{match[2]}")["sections"].find { |entry| entry["kind"] == kind }
      else
        builtin_designs.values.flat_map { |definition| definition["sections"] }.find { |entry| entry["kind"] == kind.to_s }
      end
    rescue KeyError
      nil
    end
    def selectable_designs(active: nil, user: nil)
      visible = StudioContext.visible(user)
      latest = visible.group_by { |_key, definition| definition["document_id"] }.values.map { |entries| entries.max_by { |_key, definition| definition["version"].to_i } }.to_h
      if active && !builtin_designs.key?(active)
        begin
          latest[active] = fetch(active)
        rescue KeyError
          # Keep the library usable if an obsolete template reference exists.
        end
      end
      builtin_designs.merge(latest)
    end
    def register_sections!
      super
      StudioContext.designs.values.flat_map { |definition| definition["sections"] }.each { |entry| StudioCatalog.register_entry(entry) }
    end
    def self.section_class(entry)
      klass = Class.new(DymondSite::Sections::Base)
      klass.key(entry.fetch("kind"))
      klass.template("lightek_designer")
      entry.fetch("fields").each do |field|
        options = field.slice("label", "accept").symbolize_keys
        options[:of] = field["of"].transform_values { |type| type.to_sym } if field["of"].is_a?(Hash)
        klass.field(field.fetch("name"), field.fetch("type").to_sym, **options)
      end
      klass
    end
    def self.register_entry(entry)
      klass = section_class(entry)
      DymondSite::SectionRegistry.register(klass)
      klass
    end
    def self.presenter(entry, data)
      record = Struct.new(:kind, :data).new(entry["kind"], data)
      section_class(entry).presenter_for(record)
    end
  end
  module StudioSectionRegistry
    def find(key)
      super || if key.to_s.start_with?("ld_") && (entry = Catalog.section_definition(key))
        StudioCatalog.register_entry(entry)
      end
    end
    def all
      ensure_designer_sections
      super
    end
    def manifest
      ensure_designer_sections
      super
    end
    private
    def ensure_designer_sections
      StudioContext.designs.values.each do |definition|
        definition["sections"].each { |entry| StudioCatalog.register_entry(entry) unless instance_variable_get(:@types).key?(entry["kind"]) }
      end
    end
  end
  module StudioSiteCopies
    def template_for!(site:, design:)
      template = super
      definition = Catalog.fetch(design)
      if definition["designer"] && !template.settings["lightek_studio_snapshot"]
        template.update!(settings: template.settings.merge("lightek_studio_snapshot" => definition.deep_dup))
        StudioContext.reset
      end
      template
    end
  end
  module StudioTemplateGuard
    def index
      super
      @templates = @templates.reject { |template| template.settings["lightek_studio"] || template.settings["lightek_studio_release"] }
    end
    def apply
      candidate = DymondSite::SiteTemplate.find(params[:id])
      raise ActiveRecord::RecordNotFound if candidate.settings["lightek_studio"] || candidate.settings["lightek_studio_release"]
      design_key = candidate.settings["lightek_design"].to_s
      if design_key.start_with?("ld_release_") && !Catalog.selectable_designs(user: current_user, active: Catalog.design_for(@site)).key?(design_key)
        raise ActiveRecord::RecordNotFound
      end
      super
    end
    private
    def set_template
      super
      raise ActiveRecord::RecordNotFound if @template.settings["lightek_studio"] || @template.settings["lightek_studio_release"]
    end
  end
end
