require "uri"
require "cgi"
module LightekMail
  class TemplateRenderer
    VARIABLES = %w[name email company subject].freeze
    def self.normalize(value)
      value = value.to_h.stringify_keys
      color = value.fetch("color", "#284f40").to_s
      raise ArgumentError, "Choose a six-digit hex brand color." unless color.match?(/\A#[0-9a-fA-F]{6}\z/)
      result = {"color" => color}
      {"heading" => 200, "body" => 20000, "button_label" => 120, "button_url" => 2000, "footer" => 2000, "html" => 50000, "text" => 20000}.each do |key, limit|
        result[key] = value[key].to_s
        raise ArgumentError, "Template #{key} is too long." if result[key].bytesize > limit
      end
      url = result["button_url"]
      raise ArgumentError, "Buttons must use an HTTPS URL without template variables." if url.present? && (!url.match?(%r{\Ahttps://[^\s<>"{}]+\z}) || URI.parse(url).host.blank?)
      result
    rescue URI::InvalidURIError
      raise ArgumentError, "Enter a valid HTTPS button URL."
    end
    def self.interpolate(text, values, html: false)
      text.to_s.gsub(/\{\{\s*(\w+)\s*\}\}/) do
        key = Regexp.last_match(1)
        raise ArgumentError, "Unknown template field: #{key}." unless VARIABLES.include?(key)
        value = values.fetch(key, "").to_s
        html ? CGI.escapeHTML(value) : value
      end
    end
    def self.clean_html(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("script,style,iframe,object,embed,form,input,button,svg,meta,link").remove
      Rails::HTML5::SafeListSanitizer.new.sanitize(fragment.to_html, tags: %w[p br strong em b i u s h1 h2 h3 h4 ul ol li a blockquote table thead tbody tfoot tr td th colgroup col caption div span hr img center font], attributes: %w[href title colspan rowspan cellpadding cellspacing border style width height align valign bgcolor color face size role alt src])
    end
    def self.render(document, values = {})
      d = normalize(document)
      fields = %w[heading body button_label footer].to_h { |k| [k, interpolate(d[k], values)] }
      text = d["text"].present? ? interpolate(d["text"], values) : [fields["heading"], fields["body"], [fields["button_label"], d["button_url"]].reject(&:blank?).join(": "), fields["footer"]].reject(&:blank?).join("\n\n")
      html = if d["html"].present?
        clean_html(interpolate(d["html"], values, html: true))
      else
        escape = ->(s) { CGI.escapeHTML(s.to_s).gsub("\n", "<br>") }
        button = d["button_url"].present? ? %(<p><a href="#{escape.call(d['button_url'])}" style="background:#{d['color']};color:#fff;padding:12px 20px;display:inline-block;text-decoration:none">#{escape.call(fields['button_label'])}</a></p>) : ""
        %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;font-family:Arial,sans-serif;color:#19232b"><tr><td style="padding:32px"><table role="presentation" width="100%" style="max-width:600px;margin:auto;background:#fff;border-top:5px solid #{d['color']}"><tr><td style="padding:32px"><h1>#{escape.call(fields['heading'])}</h1><p style="line-height:1.6">#{escape.call(fields['body'])}</p>#{button}<hr><p style="font-size:12px;color:#65717e">#{escape.call(fields['footer'])}</p></td></tr></table></td></tr></table>)
      end
      text = Rails::HTML5::FullSanitizer.new.sanitize(html).strip if text.blank? && html.present?
      {html: html, text: text}
    end
  end
end
