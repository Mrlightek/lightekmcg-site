# frozen_string_literal: true
module LightekDashboard
  module FormPalette
    module_function
    def luminance(value)
      source = value.to_s.strip
      hex = source.delete_prefix("#")
      rgb = if source.start_with?("#") && hex.match?(/\A[0-9a-f]{3}\z/i)
        hex.chars.map { |v| (v * 2).to_i(16) }
      elsif source.start_with?("#") && hex.match?(/\A[0-9a-f]{6}\z/i)
        hex.scan(/../).map { |v| v.to_i(16) }
      elsif (match = source.match(/\Argb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)\z/i))
        match.captures.map { |v| v.to_i.clamp(0, 255) }
      end
      return nil unless rgb
      rgb.zip([0.2126, 0.7152, 0.0722]).sum do |channel, weight|
        component = channel / 255.0
        weight * (component <= 0.04045 ? component / 12.92 : ((component + 0.055) / 1.055)**2.4)
      end
    end
    def foreground(accent)
      light = luminance(accent)
      return "var(--dd-text-primary)" if light.nil?
      (light + 0.05) / 0.05 >= 1.05 / (light + 0.05) ? "#000000" : "#ffffff"
    end
    def scheme(background)
      light = luminance(background)
      light && light > 0.179 ? "light" : "dark"
    end
  end
end
