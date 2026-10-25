# frozen_string_literal: true
module DymondDash
  module TemplateSchemaHelper
    NAV_LAYOUTS   = %w[left center right split].freeze
    FOOTER_STYLES = %w[columns minimal centered].freeze

    def template_schema
      [
        ["Colors", [
          { name: "color_bg",         type: :color },
          { name: "color_text",       type: :color },
          { name: "color_primary",    type: :color },
          { name: "color_text_muted", type: :color }
        ]],
        ["Typography", [
          { name: "font_sans", type: :string },
          { name: "font_heading", type: :string },
          { name: "font_mono", type: :string }
        ]],
        ["Layout", [
          { name: "nav_layout",   type: :select, options: NAV_LAYOUTS },
          { name: "footer_style", type: :select, options: FOOTER_STYLES }
        ]],
        ["Branding", [
          { name: "logo", type: :attachment, accept: "image/*" }
        ]]
      ]
    end

    def template_field_value(template, field)
      s = template.settings || {}
      case field[:name].to_s
      when "color_bg", "color_text", "color_primary", "color_text_muted", "font_sans", "font_heading", "font_mono"
        (s["tokens"] || {})[field[:name].to_s]
      when "nav_layout", "footer_style"
        s[field[:name].to_s]
      when "logo"
        s["logo_asset_id"]
      end
    end
  end
end
