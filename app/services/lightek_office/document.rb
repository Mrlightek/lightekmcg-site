# frozen_string_literal: true

require 'rails-html-sanitizer'

module LightekOffice
  module Document
    TAGS = %w[a b blockquote br code del div em h1 h2 h3 i li ol p pre s strike strong u ul].freeze
    ATTRIBUTES = %w[href title].freeze

    module_function

    def prepare!(content)
      LightekOffice::Content.validate!('document', content)
      html = sanitize(content)
      raise ArgumentError, 'Write some document text before saving.' if Nokogiri::HTML5.fragment(html).text.tr("\u00a0", ' ').strip.blank?

      html
    end

    def editor_html(content, rich_text:)
      return sanitize(content) if rich_text

      ERB::Util.html_escape(content.to_s).gsub(/\r\n|\r|\n/, '<br>')
    end

    def sanitize(content)
      Rails::HTML5::SafeListSanitizer.new.sanitize(content.to_s, tags: TAGS, attributes: ATTRIBUTES)
    end

    def export(content)
      "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Office document</title><body>#{sanitize(content)}</body></html>"
    end
  end
end
