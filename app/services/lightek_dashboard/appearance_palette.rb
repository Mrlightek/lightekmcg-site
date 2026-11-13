# frozen_string_literal: true
module LightekDashboard
  module AppearancePalette
    # All persisted values are plain hex colors; no arbitrary CSS is accepted.
    COLORS = {
      "page_bg" => ["Page background", "#f4f6fa"],
      "sidebar_bg" => ["Sidebar and panels", "#ffffff"],
      "topbar_bg" => ["Top bar", "#ffffff"],
      "card_bg" => ["Cards and elevated surfaces", "#ffffff"],
      "accent" => ["Accent and primary buttons", "#2563eb"],
      "accent_hover" => ["Primary button hover", "#1d4ed8"],
      "text_primary" => ["Primary text", "#172033"],
      "text_secondary" => ["Secondary text", "#596579"],
      "text_muted" => ["Muted text", "#69758a"],
      "border" => ["Borders", "#dce2eb"],
      "input_bg" => ["Field background", "#ffffff"],
      "input_text" => ["Field text", "#172033"],
      "input_border" => ["Field border", "#c5cedb"],
      "success" => ["Success status", "#16835b"],
      "danger" => ["Error status", "#c63742"]
    }.freeze
    module_function

    def valid?(value)
      value.is_a?(String) && value.match?(/\A#[0-9a-f]{6}\z/i)
    end

    def values(theme)
      tokens = theme&.tokens.to_h.stringify_keys
      # Existing themes inherit newly introduced surfaces from their own colors.
      aliases = { "page_bg" => "card_bg", "input_bg" => "card_bg", "input_text" => "text_primary", "input_border" => "border", "topbar_bg" => "sidebar_bg" }
      COLORS.to_h do |key, (_, fallback)|
        value = tokens[key]
        value = tokens[aliases[key]] unless valid?(value)
        [key, valid?(value) ? value : fallback]
      end
    end

    def validate!(tokens)
      values = tokens.to_h.stringify_keys.slice(*COLORS.keys)
      raise ArgumentError, "Choose a six-digit hex color for every Dashboard color." unless values.keys.sort == COLORS.keys.sort && values.values.all? { |value| valid?(value) }
      values
    end
  end
end
