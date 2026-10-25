# frozen_string_literal: true
module DymondDash
  module TemplateSettingsAssembler
    module_function
    TOKEN_KEYS = %w[color_bg color_text color_primary color_text_muted font_sans font_heading font_mono].freeze

    def build(params)
      tokens = {}
      TOKEN_KEYS.each { |k| tokens[k] = params[k] if params[k].present? }
      {
        "tokens"        => tokens,
        "nav_layout"    => params["nav_layout"].presence || "left",
        "footer_style"  => params["footer_style"].presence || "columns",
        "logo_asset_id" => params["logo_id"].presence
      }.compact
    end
  end
end
