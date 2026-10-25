# frozen_string_literal: true
module LightekDesign
  module WebsiteFonts
    extend ActiveSupport::Concern
    included do
      after_action :lightek_append_website_fonts, only: :show
    end
    private
    def lightek_append_website_fonts
      return unless response.media_type == "text/html" && @site && @page
      body = response.body
      return unless body.include?("</head>") && !body.include?('id="lightek-website-typography"')
      typography = render_to_string(partial: "lightek_design/website_fonts", layout: false)
      response.body = body.sub("</head>", typography + "</head>")
      response.delete_header("Content-Length")
    end
  end
end
