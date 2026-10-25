# frozen_string_literal: true
module LightekDesign
  module StudioBlocks
    module_function
    def field(name, type = "string", label = nil, **options)
      {"name" => name, "type" => type, "label" => label || name.humanize}.merge(options.stringify_keys)
    end
    def definitions
      common = [field("eyebrow"), field("heading"), field("body", "text"), field("image_url"), field("image_alt"), field("cta_label"), field("cta_url")]
      @definitions ||= {
        "hero" => {"name" => "Hero", "fields" => common, "data" => {"eyebrow" => "Your next chapter", "heading" => "Make something remarkable.", "body" => "Tell your story, introduce your business, and give visitors a clear next step.", "cta_label" => "Get started", "cta_url" => "#contact"}},
        "text" => {"name" => "Text", "fields" => common.first(3), "data" => {"heading" => "A story worth sharing", "body" => "Write your introduction here."}},
        "split" => {"name" => "Image & text", "fields" => common, "data" => {"heading" => "Show the work.", "body" => "Pair a strong image with the details that matter.", "cta_label" => "Learn more", "cta_url" => "#contact"}},
        "cards" => {"name" => "Cards", "fields" => common.first(3) + [field("items", "collection", "Cards", of: {"title" => "string", "body" => "text", "image_url" => "string", "url" => "string"})], "data" => {"heading" => "What we do", "items" => [{"title" => "First offering", "body" => "Describe the benefit."}, {"title" => "Second offering", "body" => "Describe the benefit."}, {"title" => "Third offering", "body" => "Describe the benefit."}]}},
        "stats" => {"name" => "Statistics", "fields" => common.first(3) + [field("items", "collection", "Statistics", of: {"value" => "string", "label" => "string"})], "data" => {"heading" => "Our impact", "items" => [{"value" => "01", "label" => "Replace with a verified figure"}, {"value" => "02", "label" => "Replace with a verified figure"}]}},
        "cta" => {"name" => "Call to action", "fields" => common.reject { |item| %w[image_url image_alt].include?(item["name"]) }, "data" => {"heading" => "Ready for the next step?", "body" => "Give visitors one clear action.", "cta_label" => "Contact us", "cta_url" => "mailto:hello@example.com"}},
        "image" => {"name" => "Image", "fields" => [field("image_url"), field("image_alt"), field("body", "text", "Caption")], "data" => {"image_alt" => "Describe the image", "body" => "Add an image and an optional caption."}},
        "footer" => {"name" => "Footer", "fields" => [field("heading"), field("body", "text"), field("cta_label"), field("cta_url")], "data" => {"heading" => "Your brand", "body" => "Contact details and copyright.", "cta_label" => "Get in touch", "cta_url" => "mailto:hello@example.com"}}
      }
    end
    def schema_for(section)
      if section["block"].present?
        definitions.fetch(section["block"]).fetch("fields")
      elsif (source = Catalog.builtin_designs.values.flat_map { |design| design["sections"] }.find { |entry| entry["kind"] == section["source_kind"] })
        source.fetch("fields")
      else
        klass = DymondSite::SectionRegistry.find(section["source_kind"])
        raise ArgumentError, "Choose a supported section." unless klass && !section["source_kind"].to_s.start_with?("ld_")
        JSON.parse(klass.schema.to_json)
      end
    end
    def sources
      Catalog.builtin_designs.values.flat_map { |design| design["sections"].map { |entry| {"kind" => entry["kind"], "name" => "#{design['name']} · #{entry['title']}", "fields" => entry["fields"], "data" => entry["data"]} } } +
        DymondSite::SectionRegistry.all.reject { |klass| klass.key.start_with?("ld_") || Catalog.builtin_designs.values.any? { |d| d["sections"].any? { |s| s["kind"] == klass.key } } }.map { |klass| {"kind" => klass.key, "name" => klass.key.humanize, "fields" => JSON.parse(klass.schema.to_json), "data" => {}} }
    end
  end
end
