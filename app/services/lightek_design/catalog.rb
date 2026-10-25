# frozen_string_literal: true
require "json"
require "uri"
module LightekDesign
  module Catalog
    module_function

    def designs
      @designs ||= JSON.parse(Rails.root.join("config/lightek_designs/catalog.json").read).freeze
    end

    def fetch(key) = designs.fetch(key.to_s)
    def design_for(site) = site&.active_template&.settings.to_h.fetch("lightek_design", nil)
    def active?(site) = designs.key?(design_for(site))
    def section_definitions = designs.values.flat_map { |design| design.fetch("sections") }
    def section_definition(kind) = section_definitions.find { |entry| entry.fetch("kind") == kind.to_s }

    def value(presenter, key, default)
      data = presenter.respond_to?(:data) ? presenter.data.to_h : presenter.to_h
      data.key?(key) ? data[key].to_s : default
    end

    def safe_url(value, image: false)
      text = value.to_s.strip
      return "#" if text.empty? || text.match?(/[\x00-\x20\\]/)
      uri = URI.parse(text)
      return text if uri.scheme.nil? && !text.start_with?("//")
      allowed = image ? %w[https http] : %w[https http mailto tel]
      allowed.include?(uri.scheme.to_s.downcase) ? text : "#"
    rescue URI::InvalidURIError
      "#"
    end

    def register_sections!
      section_definitions.each do |entry|
        klass = Class.new(DymondSite::Sections::Base)
        klass.key(entry.fetch("kind"))
        klass.template(entry.fetch("kind"))
        entry.fetch("fields").each do |field|
          klass.field(field.fetch("name"), field.fetch("type").to_sym, label: field.fetch("label"))
        end
        DymondSite::SectionRegistry.register(klass)
      end
    end
  end
end
