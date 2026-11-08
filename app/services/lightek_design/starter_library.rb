# frozen_string_literal: true
require "json"
require "nokogiri"

module LightekDesign
  # Installed defaults use the existing SectionRegistry and Studio document schema.
  # HTML/CSS is versioned source; clients edit content arrays without executing JS.
  module StarterLibrary
    module_function
    def directory = Rails.root.join("config/lightek_designs/starters")
    def manifests
      @manifests ||= directory.join("manifests").glob("*.json").sort.to_h do |file|
        manifest = JSON.parse(file.read)
        [manifest.fetch("template"), manifest]
      end.freeze
    end
    def fetch(key) = manifests.fetch(key.to_s)
    def section_sources(key)
      @sources ||= {}
      @sources[key] ||= begin
        fetch(key)
        doc = Nokogiri::HTML5.parse(directory.join("#{key}.html").read)
        doc.css("script,style,link,meta").remove
        doc.css(".pp,.ph,.ph2").each do |node|
          node["data-img"] ||= node["data-cap"].presence || node.parent.at_css("h3")&.text.to_s
        end
        doc.css("[data-section]").to_h do |node|
          section_key = node["id"].presence || node["data-section"]
          [section_key, node.to_html]
        end.freeze
      end
    end
    def source(key, section_key) = section_sources(key).fetch(section_key.to_s)
    def content_for(html)
      fragment = Nokogiri::HTML5.fragment(html)
      {"copy" => HtmlDocument.text_nodes(fragment).map(&:text),
        "links" => fragment.css("a[href]").map { |node| node["href"] },
        "images" => fragment.css("img,[data-img]").map { |node| node["src"].to_s }}
    end
    def normalize_data(raw)
      raise ArgumentError, "Invalid starter content" unless raw.is_a?(Hash)
      key, section_key = raw.values_at("template_key", "section_key").map(&:to_s)
      source(key, section_key)
      result = {"template_key" => key, "section_key" => section_key}
      %w[copy links images].each do |field|
        values = raw[field] || []
        raise ArgumentError, "Starter fields support up to 500 values" unless values.is_a?(Array) && values.length <= 500
        result[field] = values.map { |value| value.to_s.first(field == "copy" ? 20_000 : 2000) }
      end
      result
    rescue KeyError
      raise ArgumentError, "Choose an installed starter section"
    end
    def designs
      @designs ||= manifests.to_h do |key, manifest|
        tokens = manifest.fetch("theme").fetch("tokens")
        definition = {"name" => manifest.dig("meta", "brand"), "description" => manifest.dig("meta", "description"),
          "starter" => true, "industry" => manifest.fetch("industry"), "base_design" => "plain", "version" => 1,
          "fonts" => {"font_sans" => tokens.fetch("fb"), "font_heading" => tokens.fetch("fh"), "font_mono" => "DM Mono"},
          "tokens" => {"color_bg" => tokens.fetch("bg"), "color_text" => tokens.fetch("ink"), "color_primary" => tokens.fetch("a"), "color_text_muted" => tokens.fetch("mut")},
          "sections" => section_sources(key).map do |section_key, html|
            node = Nokogiri::HTML5.fragment(html).element_children.first
            {"kind" => "starter_#{key.tr('-', '_')}_#{section_key.tr('-', '_')}", "title" => "#{node['data-section'].humanize} · #{node.at_css('h1,h2')&.text.to_s.first(70)}",
              "block" => "starter", "designer" => true, "anchor" => node["id"].to_s,
              "section_type" => node["data-section"], "chrome_header" => node.name == "header", "chrome_footer" => node.name == "footer",
              "fields" => StudioBlocks.definitions.fetch("starter").fetch("fields"),
              "style" => StudioDocument::STYLE_DEFAULTS.merge("padding" => 0, "width" => 1600, "radius" => 0),
              "data" => {"template_key" => key, "section_key" => section_key}.merge(content_for(html))}
          end}
        ["starter_#{key.tr('-', '_')}", definition]
      end.freeze
    end

    def render_html(data, site:, preview:, authenticity_token:)
      data = normalize_data(data)
      fragment = Nokogiri::HTML5.fragment(source(data["template_key"], data["section_key"]))
      HtmlDocument.text_nodes(fragment).each_with_index { |node, i| node.content = data["copy"][i] if data["copy"].length > i }
      fragment.css("a[href]").each_with_index { |node, i| node["href"] = Catalog.safe_url(data["links"][i]) if data["links"].length > i }
      fragment.css("img,[data-img]").each_with_index do |node, i|
        url = data["images"][i].to_s
        next if url.blank? || Catalog.safe_url(url, image: true) == "#"
        if node.name == "img"
          node["src"] = url
        else
          image = Nokogiri::XML::Node.new("img", fragment.document)
          image["src"] = url; image["alt"] = node["data-img"].to_s; image["loading"] = "lazy"
          image["style"] = "width:100%;height:100%;object-fit:cover"
          node.children.remove; node.add_child(image)
        end
      end
      # These are installed sources, never user-supplied HTML. Their scripts are
      # excluded; only this application's maintained runtime supplies behavior.
      fragment.css("script,iframe,object,embed").remove
      fragment.css("*").each { |node| node.attribute_nodes.select { |a| a.name.start_with?("on") }.each(&:remove) }
      fragment.css("form").each do |form|
        form["action"] = "/website/template-inquiries"; form["method"] = "post"
        form["data-preview"] = "true" if preview
        form.remove_attribute("data-ok"); form.remove_attribute("data-endpoint")
        {"authenticity_token" => authenticity_token, "template_key" => data["template_key"], "section_key" => data["section_key"]}.each do |name, value|
          input = Nokogiri::XML::Node.new("input", fragment.document)
          input["type"] = "hidden"; input["name"] = name; input["value"] = value.to_s; form.add_child(input)
        end
        form.css('[type="submit"]').each { |button| button["disabled"] = "disabled" } if preview
        form.css('[type="submit"]').each { |button| button.content = "Send request" }
        status = Nokogiri::XML::Node.new("p", fragment.document)
        status["class"] = "template-status"; status["role"] = "status"
        status.content = preview ? "Preview only. Requests are saved when this page is published." : "Send an inquiry. Availability and payment are confirmed separately."
        form.add_child(status)
      end
      # Published booking experiences replace inquiry-only calls to action. Keep
      # contact forms available for questions, without pretending they reserved time.
      if site && LightekReservations::Resource.available.where(site_id: site.id).exists?
        fragment.css('a[href],button').each do |node|
          next unless node.text.strip.match?(/\A(?:book|reserve|schedule|make a reservation|request an appointment)/i)
          next if node.ancestors('form').any?
          node.name = 'a'
          node['href'] = "/reservations"
          node.remove_attribute('type')
          node.remove_attribute('data-add')
        end
        fragment.css('form').each do |form|
          next unless form.at_css('[name="date"],[name="time"],[type="date"],[type="datetime-local"]')
          link = Nokogiri::XML::Node.new('a', fragment.document)
          link['href'] = '/reservations'
          link['class'] = 'btn'
          link.content = 'Choose an available experience & book'
          form.add_previous_sibling(link)
        end
      end
      # Demo cart counters and fake audio playback never impersonate real commerce.
      fragment.css("[data-add]").each { |button| button.name = "a"; button["href"] = "#contact"; button.content = "Ask about this item"; button.remove_attribute("data-add") }
      fragment.css(".trk button").each { |button| button["disabled"] = "disabled"; button["title"] = "Add an audio source before offering playback" }
      if data["section_key"] == "nav" && data["template_key"].start_with?("boutique-")
        fragment.at_css("#navcta").content = "Contact the shop"
      end
      if (credit = fragment.at_css("footer .cr span:last-child"))
        credit.content = TemplateBranding.new(site).credit
        credit["data-template-credit"] = "true"
      end
      fragment.to_html
    end
  end
end
