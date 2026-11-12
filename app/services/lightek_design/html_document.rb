# frozen_string_literal: true
require "nokogiri"
require "crass"

module LightekDesign
  # HTML remains editable source. Shadow roots preserve the supplied CSS without
  # changing the host website's navigation, dashboard, or other sections.
  class HtmlDocument
    MAX_BYTES = 500_000
    TAGS = %w[a abbr article aside b blockquote br button caption code col colgroup dd details div dl dt em figcaption figure footer h1 h2 h3 h4 h5 h6 header hr i img label li main nav ol p picture pre s section small source span strong sub summary sup table tbody td th thead time tr u ul video audio svg g path circle ellipse rect line polygon polyline defs symbol use linearGradient radialGradient stop title].freeze
    ATTRIBUTES = %w[id class style href src srcset alt title width height viewBox viewbox fill stroke stroke-width stroke-opacity stroke-linejoin d points cx cy r rx ry x y x1 x2 y1 y2 offset stop-color opacity role aria-label aria-hidden aria-current aria-expanded aria-controls loading controls poster type media sizes target rel colspan rowspan datetime hidden data-section data-icon data-img data-l data-h data-lightek-route data-lightek-navigation data-lightek-products data-lightek-blog].freeze

    def self.normalize_data(raw)
      raise ArgumentError, "Invalid HTML section." unless raw.is_a?(Hash)
      raise ArgumentError, "Section source exceeds 500 KB." if raw.to_json.bytesize > MAX_BYTES
      %w[copy links images].each { |key| raise ArgumentError, "Invalid imported content." if raw[key] && (!raw[key].is_a?(Array) || raw[key].length > 500) }
      {"copy" => Array(raw["copy"]).map { |value| value.to_s.first(20_000) }, "links" => Array(raw["links"]).map { |value| value.to_s.first(2000) }, "images" => Array(raw["images"]).map { |value| value.to_s.first(2000) },
        "html" => clean_html(raw["html"]), "css" => clean_css(raw["css"]), "body_class" => raw["body_class"].to_s.first(500),
        "font_stylesheets" => raw["font_stylesheets"].to_s.lines.map(&:strip).select { |url| url.match?(/\Ahttps:\/\/fonts\.googleapis\.com\/css[^\s<>]*\z/) }.first(5).join("\n")}
    end

    def self.text_nodes(fragment)
      fragment.xpath(".//text()").reject { |node| node.text.strip.empty? || node.ancestors.any? { |parent| parent.name == "svg" } }
    end

    def self.editable_content(html)
      fragment = Nokogiri::HTML5.fragment(html)
      {"copy" => text_nodes(fragment).map(&:text), "links" => fragment.css("a[href]").map { |node| node["href"] }, "images" => fragment.css("img[src]").map { |node| node["src"] }}
    end

    def self.render_html(source)
      fragment = Nokogiri::HTML5.fragment(source.fetch("html"))
      text_nodes(fragment).each_with_index { |node, index| node.content = source["copy"][index] if source["copy"].length > index }
      fragment.css("a[href]").each_with_index { |node, index| node["href"] = Catalog.safe_url(source["links"][index]) if source["links"].length > index }
      fragment.css("img[src]").each_with_index { |node, index| node["src"] = Catalog.safe_url(source["images"][index], image: true) if source["images"].length > index }
      clean_html(fragment.to_html)
    end

    def self.clean_html(html)
      fragment = Nokogiri::HTML5.fragment(html.to_s)
      fragment.css("script,iframe,object,embed,link,meta,base,style,form,input,textarea,select").each(&:remove)
      # CSS is allowed in the isolated preview, but never executable attributes.
      fragment.traverse do |node|
        next unless node.element?
        node.attribute_nodes.each do |attribute|
          name = attribute.name
          if !ATTRIBUTES.include?(name) || name.start_with?("on")
            node.remove_attribute(name)
          elsif %w[href src poster].include?(name)
            value = attribute.value.strip
            node.remove_attribute(name) unless value.start_with?("#") || Catalog.safe_url(value, image: name != "href") != "#"
          elsif name == "style"
            node[name] = clean_css(attribute.value, declarations: true)
          elsif name == "srcset"
            node.remove_attribute(name) # Relative asset bundles need explicit resolution.
          end
        end
        node.replace(node.children) unless TAGS.include?(node.name)
      end
      fragment.to_html
    end

    def self.safe_css_tokens?(tokens)
      Array(tokens).all? do |token|
        next true unless token.is_a?(Hash)
        if token[:node] == :url
          value = token[:value].to_s
          value.start_with?("#") || Catalog.safe_url(value, image: true) != "#"
        elsif token[:node] == :function && %w[url expression].include?(token[:name].to_s.downcase)
          value = Array(token[:value]).find { |item| item[:node] == :string }&.dig(:value).to_s
          token[:name].to_s.downcase == "url" && (value.start_with?("#") || Catalog.safe_url(value, image: true) != "#")
        else
          token.values.grep(Array).all? { |value| safe_css_tokens?(value) }
        end
      end
    end

    def self.css_properties(nodes)
      nodes.filter_map do |node|
        next unless node[:node] == :property && safe_css_tokens?(node[:children])
        next if %w[behavior -moz-binding].include?(node[:name].to_s.downcase)
        "#{node[:name]}:#{Crass::Parser.stringify(node[:children])}#{'!important' if node[:important]};"
      end.join
    end

    def self.css_rules(nodes, shadow: false)
      nodes.filter_map do |node|
        if node[:node] == :style_rule
          selector = node.fetch(:selector).fetch(:value)
          if shadow
            selector = selector.gsub(/(?<![\w.#-])(?:html|:root)(?![\w-])/, ":host").gsub(/(?<![\w.#-])body(?![\w-])/, ".li-body")
          end
          "#{selector}{#{css_properties(node[:children])}}"
        elsif node[:node] == :at_rule && %w[media supports font-face keyframes -webkit-keyframes layer container].include?(node[:name].to_s.downcase) && node[:block] && safe_css_tokens?(node[:prelude])
          contents = Crass::Parser.stringify(node[:block])
          inner = if node[:name].downcase == "font-face"
            css_properties(Crass.parse_properties(contents))
          else
            css_rules(Crass.parse(contents), shadow: shadow && !node[:name].include?("keyframes"))
          end
          "@#{node[:name]} #{Crass::Parser.stringify(node[:prelude]).strip}{#{inner}}"
        end
      end.join
    end

    def self.clean_css(css, declarations: false)
      result = declarations ? css_properties(Crass.parse_properties(css.to_s)) : css_rules(Crass.parse(css.to_s))
      result.gsub("<") { "\\3c " }
    end

    def self.shadow_css(css)
      css_rules(Crass.parse(clean_css(css)), shadow: true).gsub("<") { "\\3c " }
    end

    def self.palette(css)
      properties = Crass.parse(css).select { |rule| rule[:node] == :style_rule && rule.dig(:selector, :value).match?(/:root|html|body/) }
        .flat_map { |rule| rule[:children] }.select { |entry| entry[:node] == :property }.to_h { |entry| [entry[:name], entry[:value].strip] }
      aliases = {"color_bg" => %w[--color-bg --bg --background], "color_text" => %w[--color-text --ink --text], "color_primary" => %w[--color-primary --primary --accent --cy], "color_text_muted" => %w[--color-text-muted --mut --muted]}
      StudioDocument::TOKEN_DEFAULTS.merge(aliases.filter_map do |key, names|
        value = names.filter_map { |name| properties[name] }.find { |candidate| candidate.match?(/\A#[a-f0-9]{6}\z/i) }
        [key, value] if value
      end.to_h)
    end

    def self.typography(css)
      rules=Crass.parse(css).select{|rule|rule[:node]==:style_rule}
      extract=->(pattern) do
        rule=rules.find{|candidate|candidate.dig(:selector,:value).match?(pattern)}
        properties=Array(rule&.dig(:children)).select{|node|node[:node]==:property}
        family=properties.find{|node|node[:name]=='font-family'}&.dig(:value)
        family ||= properties.find{|node|node[:name]=='font'}&.dig(:value)&.match(/(['"])([^'"]+)\1/)&.[](2)
        family.to_s.strip if family.present? && Fonts.valid_stack?(family.to_s.strip)
      end
      StudioDocument::FONT_DEFAULTS.merge({"font_sans"=>extract.call(/(?:\A|,)\s*body(?:\s|,|\z)/),"font_heading"=>extract.call(/(?:\A|,)\s*h[1-6](?:\s|,|\z)/)}.compact)
    end

    def self.convert(html:, css: "", name: nil, product_selector: nil, blog_selector: nil)
      raise ArgumentError, "Choose an HTML file up to 500 KB." unless html.to_s.bytesize.between?(1, MAX_BYTES)
      raise ArgumentError, "Choose a CSS file up to 500 KB." if css.to_s.bytesize > MAX_BYTES
      doc = Nokogiri::HTML5.parse(html)
      styles = clean_css(([css] + doc.css("style").map(&:text)).join("\n"))
      warnings = []
      warnings << "JavaScript, forms and event handlers need service wiring; they are not executed by imported sections." if doc.at_css("script,form,[onclick]")
      warnings << "External stylesheets and relative assets are not bundled. Upload CSS and use hosted image URLs." if doc.css('link[rel="stylesheet"]').any? || doc.css("[src]").any? { |n| !n['src'].to_s.match?(/\A(?:https?:|#)/) }
      # Font stylesheet links are retained only for Google's font CSS endpoint.
      fonts = doc.css('link[rel="stylesheet"]').filter_map { |link| link['href'] if link['href'].to_s.start_with?("https://fonts.googleapis.com/css") }.join("\n")
      body = doc.at_css("body")
      body.css("script,style,link,meta").each(&:remove)
      roots = body.element_children.flat_map { |node| node.name == "main" && !(blog_selector.present? && node.matches?(blog_selector)) ? node.element_children.to_a : [node] }
      roots.reject! { |node| node.name == "svg" && node['height'] == "0" }
      raise ArgumentError, "No visible HTML sections found." if roots.empty?
      raise ArgumentError, "Split this design into at most 30 top-level sections." if roots.length > 30
      symbols = doc.css("svg").select { |node| node.at_css("symbol,defs") }.map(&:to_html).join
      sections = roots.map do |node|
        if blog_selector.present? && (node.matches?(blog_selector) || node.at_css(blog_selector))
          {"id"=>SecureRandom.hex(6),"title"=>"Journal", "anchor"=>"journal", "source_kind"=>"lightek_blog_index", "data"=>ContentSections.definitions.first["data"].deep_dup, "style"=>StudioDocument::STYLE_DEFAULTS.deep_dup}
        elsif product_selector.present? && (node.matches?(product_selector) || node.at_css(product_selector))
          warnings << "The product area uses this website's published products and Lightek checkout."
          {"id" => SecureRandom.hex(6), "title" => "Live products", "anchor" => "products", "source_kind" => "lightek_product_grid", "data" => CommerceSections.definitions.first["data"].deep_dup, "style" => StudioDocument::STYLE_DEFAULTS.deep_dup}
        else
          heading = node.at_css("h1,h2,h3")&.text.to_s.strip.presence || node['id'].presence || node.name.humanize
          # Preserve main's classes/IDs for selectors such as main > .hero.
          markup = node.to_html
          if node.parent.name == "main"
            parent = node.parent.dup(0)
            parent.inner_html = markup
            markup = parent.to_html
          end
          {"id" => SecureRandom.hex(6), "title" => heading.first(120), "anchor" => "", "block" => "html", "chrome_header" => node.name == "header", "chrome_footer" => node.name == "footer", "data" => {"html" => clean_html(symbols + markup), "css" => styles, "font_stylesheets" => fonts, "body_class" => body['class'].to_s}.merge(editable_content(clean_html(symbols + markup))), "style" => StudioDocument::STYLE_DEFAULTS.merge("padding" => 0, "width" => 1600)}
        end
      end
      if product_selector.present? && sections.count { |section| section["source_kind"] == "lightek_product_grid" } != 1
        raise ArgumentError, "Choose a selector matching exactly one visible product container."
      end
      if blog_selector.present? && sections.count { |section| section["source_kind"] == "lightek_blog_index" } != 1
        raise ArgumentError, "Choose a blog layout with exactly one main content area."
      end
      # Dynamic visibility effects cannot leave content invisible without scripts.
      warnings << "Review script-generated areas in preview; HTML import does not execute JavaScript to generate missing content."
      document = {"name" => name.to_s.strip.presence || doc.at_css("title")&.text.to_s.first(120).presence || "Imported website", "description" => "Imported HTML/CSS design", "base_design" => "plain", "fonts" => typography(styles), "tokens" => palette(styles), "sections" => sections}
      [StudioDocument.normalize(document), warnings.uniq]
    rescue Nokogiri::CSS::SyntaxError
      raise ArgumentError, "Enter a valid product area CSS selector."
    end
  end
end
