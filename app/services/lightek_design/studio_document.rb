# frozen_string_literal: true
require "digest"
module LightekDesign
  class StudioDocument
    class Conflict < StandardError; end
    COLOR_KEYS = %w[color_bg color_text color_primary color_text_muted].freeze
    STYLE_NUMBERS = {"padding" => (0..160), "width" => (480..1600), "gap" => (0..64), "columns" => (1..4), "radius" => (0..48), "heading_size" => (20..120)}.freeze
    STYLE_DEFAULTS = {"padding" => 64, "width" => 1200, "gap" => 24, "columns" => 3, "radius" => 8, "heading_size" => 48, "align" => "left", "background" => "transparent", "color" => "inherit"}.freeze
    FONT_DEFAULTS = {"font_sans" => "Inter", "font_heading" => "Inter", "font_mono" => "DM Mono"}.freeze
    TOKEN_DEFAULTS = {"color_bg" => "#101216", "color_text" => "#f5f5f5", "color_primary" => "#c8ff00", "color_text_muted" => "#a3a8b2"}.freeze
    module Permissions
      module_function
      def owns?(record, user)
        user && (user.role.to_s == "super_admin" || record.settings.dig("lightek_studio", "owner_id").to_s == user.id.to_s)
      end
    end
    class << self
      def records = DymondSite::SiteTemplate.where("key LIKE ?", "ld_document_%").order(updated_at: :desc)
      def documents_for(user, offset: 0, limit: 24)
        return [] unless user
        scope = records
        unless user.role.to_s == "super_admin"
          scope = scope.where("CAST(settings -> 'lightek_studio' ->> 'owner_id' AS TEXT) = ?", user.id.to_s)
        end
        scope.offset(offset).limit(limit).reject { |record| record.settings.dig("lightek_studio", "archived") }
      end
      def find_for!(id, user)
        record = records.find(id)
        raise ActiveRecord::RecordNotFound unless Permissions.owns?(record, user)
        record
      end
      def metadata(record) = record.settings.fetch("lightek_studio")
      def draft(record) = metadata(record).fetch("draft").deep_dup
      def revision(record) = metadata(record).fetch("revision", 1)
      def create!(user:, name:, source: nil)
        raise ArgumentError, "Administrator access is required." unless user&.role.to_s.in?(%w[admin super_admin])
        document = if source.present?
          definition = Catalog.fetch(source)
          if definition["designer"] && user.role.to_s != "super_admin" && definition["owner_id"].to_s != user.id.to_s
            raise ActiveRecord::RecordNotFound
          end
          from_definition(definition)
        else
          {"name" => "New design", "description" => "", "base_design" => "plain", "fonts" => FONT_DEFAULTS, "tokens" => TOKEN_DEFAULTS, "sections" => [new_block("hero"), new_block("cards"), new_block("cta"), new_block("footer")]}
        end
        document["name"] = name.to_s.strip.presence || "#{document['name']} copy"
        document = normalize(document)
        identifier = SecureRandom.hex(10)
        DymondSite::SiteTemplate.create!(name: "Design workspace #{identifier}", key: "ld_document_#{identifier}", description: document["description"], settings: {"lightek_studio" => {"owner_id" => user.id, "revision" => 1, "draft" => document, "releases" => [], "assets" => []}})
      end
      def from_definition(definition)
        {"name" => definition["name"], "description" => definition["description"], "base_design" => definition["base_design"] || (definition["name"] == "YBNC" ? "ybnc" : "vinylctrl"), "fonts" => definition["fonts"], "tokens" => definition["tokens"], "sections" => definition.fetch("sections").map do |entry|
          {"id" => SecureRandom.hex(6), "anchor" => entry["anchor"].to_s, "title" => entry["title"], "block" => entry["block"], "source_kind" => (entry["block"].present? ? nil : entry["render_kind"] || entry["kind"]), "data" => entry["data"], "style" => entry["style"] || STYLE_DEFAULTS.merge("padding" => 0, "width" => 1600, "radius" => 0)}
        end}
      end
      def new_block(key)
        block = StudioBlocks.definitions.fetch(key)
        {"id" => SecureRandom.hex(6), "anchor" => {"hero" => "home", "cards" => "services", "cta" => "contact", "footer" => "footer"}.fetch(key, ""), "title" => block["name"], "block" => key, "data" => block["data"].deep_dup, "style" => STYLE_DEFAULTS.deep_dup}
      end
      def normalize(raw)
        raise ArgumentError, "The design must be an object." unless raw.is_a?(Hash)
        raise ArgumentError, "Design is too large." if raw.to_json.bytesize > 700_000
        name = raw["name"].to_s.strip
        raise ArgumentError, "Give the design a name (1–120 characters)." unless name.length.between?(1, 120)
        raise ArgumentError, "Choose a valid base style." unless %w[plain vinylctrl ybnc].include?(raw["base_design"])
        raise ArgumentError, "Invalid typography or palette." unless raw.fetch("tokens", {}).is_a?(Hash) && raw.fetch("fonts", {}).is_a?(Hash)
        tokens = COLOR_KEYS.to_h { |key| [key, color(raw.fetch("tokens", {}).fetch(key, TOKEN_DEFAULTS[key]))] }
        fonts = FONT_DEFAULTS.to_h do |key, default|
          value = raw.fetch("fonts", {}).fetch(key, default).to_s.strip
          value = default if value.blank?
          raise ArgumentError, "Choose a valid font family." unless Fonts.valid_stack?(value)
          [key, value]
        end
        sections = raw["sections"]
        raise ArgumentError, "A design supports 1–30 sections." unless sections.is_a?(Array) && sections.length.between?(1, 30)
        seen = []
        anchors = []
        normalized = sections.map do |section|
          raise ArgumentError, "Invalid section." unless section.is_a?(Hash)
          id = section["id"].to_s
          raise ArgumentError, "Each section needs a unique ID." unless id.match?(/\A[a-z0-9]{8,32}\z/) && !seen.include?(id)
          seen << id
          anchor = section["anchor"].to_s
          unless anchor.empty? || (anchor.match?(/\A[a-zA-Z][a-zA-Z0-9_-]{0,60}\z/) && !anchors.include?(anchor))
            raise ArgumentError, "Section anchors must be unique and contain only letters, numbers, hyphens and underscores."
          end
          anchors << anchor unless anchor.empty?
          block, source = section["block"].presence, section["source_kind"].presence
          raise ArgumentError, "Choose one section type." if block && source
          entry = {"id" => id, "anchor" => anchor, "title" => section["title"].to_s.first(120), "block" => block, "source_kind" => source, "style" => normalize_style(section["style"] || {})}
          schema = StudioBlocks.schema_for(entry)
          entry["data"] = normalize_data(section["data"] || {}, schema)
          entry
        end
        {"name" => name, "description" => raw["description"].to_s.first(1000), "base_design" => raw["base_design"], "tokens" => tokens, "fonts" => fonts, "sections" => normalized}
      rescue KeyError
        raise ArgumentError, "The design contains an unknown section type."
      end
      def color(value, special: [])
        text = value.to_s
        raise ArgumentError, "Choose a valid color." unless text.match?(/\A#[0-9a-f]{6}\z/i) || special.include?(text)
        text
      end
      def normalize_style(raw)
        raise ArgumentError, "Invalid section style." unless raw.is_a?(Hash)
        style = STYLE_DEFAULTS.merge(raw.slice(*STYLE_DEFAULTS.keys))
        STYLE_NUMBERS.each do |key, range|
          number = Integer(style[key].to_s, 10) rescue nil
          raise ArgumentError, "#{key.humanize} is outside the supported range." unless number && range.cover?(number)
          style[key] = number
        end
        raise ArgumentError, "Choose a valid alignment." unless %w[left center right].include?(style["align"])
        style["background"] = color(style["background"], special: ["transparent"])
        style["color"] = color(style["color"], special: ["inherit"])
        style
      end
      def normalize_data(raw, schema)
        raise ArgumentError, "Invalid section content." unless raw.is_a?(Hash)
        schema.each_with_object({}) do |field, data|
          key = field.fetch("name").to_s
          value = raw[key]
          case field["type"].to_s
          when "collection"
            rows = value || []
            raise ArgumentError, "Collections support up to 30 items." unless rows.is_a?(Array) && rows.length <= 30
            if field["of"].is_a?(Hash)
              sub = field["of"].map { |name, type| {"name" => name, "type" => type} }
              data[key] = rows.map { |row| normalize_data(row, sub) }
            else
              data[key] = rows.map { |row| row.to_s.first(2000) }
            end
          when "attachment"
            id = raw["#{key}_id"] || value
            raise ArgumentError, "Choose an image from uploaded assets." if id.present? && !id.to_s.match?(/\A\d+\z/)
            data["#{key}_id"] = id.to_s if id.present?
          when "boolean"
            data[key] = [true, "1", "true"].include?(value)
          when "animation"
            data[key] = value.is_a?(Hash) ? value.slice("effect", "trigger", "duration", "delay", "stagger", "ease") : {}
          when "richtext"
            data[key] = ActionController::Base.helpers.sanitize(value.to_s.first(20_000))
          else
            data[key] = value.to_s.first(20_000)
          end
        end
      end
      def update!(record:, document:, expected_revision:)
        normalized = normalize(document)
        record.with_lock do
          check_revision!(record, expected_revision)
          meta = metadata(record).deep_dup
          meta["draft"] = normalized
          meta["revision"] += 1
          record.update!(settings: record.settings.merge("lightek_studio" => meta))
        end
        record
      end
      def check_revision!(record, expected)
        raise Conflict, "This design changed in another tab. Reload before saving so those changes are preserved." unless Integer(expected.to_s, 10) == revision(record)
      rescue ArgumentError
        raise Conflict, "Reload the design before saving."
      end
      def publish!(record:, document:, expected_revision:)
        normalized = normalize(document)
        release = nil
        record.with_lock do
          check_revision!(record, expected_revision)
          meta = metadata(record).deep_dup
          digest = Digest::SHA256.hexdigest(normalized.to_json)
          if meta["last_published_digest"] == digest && meta.fetch("releases", []).any?
            return DymondSite::SiteTemplate.find_by!(key: meta["releases"].last.fetch("key"))
          end
          version = meta.fetch("releases", []).length + 1
          key = "ld_release_#{record.id}_v#{version}"
          definition = definition_for(normalized, key: key, document_id: record.id, version: version)
          definition["owner_id"] = meta["owner_id"]
          release = DymondSite::SiteTemplate.create!(name: "Design release #{record.id} v#{version}", key: key,
            description: normalized["description"], settings: {"lightek_studio_release" => definition})
          meta["draft"] = normalized
          meta["revision"] += 1
          meta["last_published_digest"] = digest
          meta["releases"] = meta.fetch("releases", []) + [{"key" => key, "version" => version, "released_at" => Time.current.iso8601}]
          record.update!(settings: record.settings.merge("lightek_studio" => meta))
        end
        StudioContext.reset
        definition = release.settings.fetch("lightek_studio_release")
        definition["sections"].each { |entry| StudioCatalog.register_entry(entry) }
        release
      end
      def definition_for(document, key:, document_id:, version:)
        {"name" => document["name"], "description" => document["description"], "designer" => true, "document_id" => document_id, "version" => version,
          "base_design" => document["base_design"], "fonts" => document["fonts"], "tokens" => document["tokens"], "sections" => document["sections"].map do |section|
            {"kind" => "ld_#{document_id}_v#{version}_#{section['id']}", "anchor" => section["anchor"], "title" => section["title"], "fields" => StudioBlocks.schema_for(section), "data" => section["data"], "block" => section["block"], "render_kind" => section["source_kind"], "style" => section["style"], "designer" => true,
              "chrome_footer" => section["block"] == "footer" || %w[vinylctrl_waitlist ybnc_footer].include?(section["source_kind"])}
          end}
      end
    end
  end
end
