# frozen_string_literal: true
require "uri"
require "json"
module LightekDesign
  module Fonts
    module_function
    SYSTEM = %w[system-ui sans-serif serif monospace cursive fantasy ui-sans-serif ui-serif ui-monospace Arial Helvetica Verdana Georgia Tahoma Times Courier inherit initial].freeze
    CATALOG = {
      "Sans serif" => ["Inter", "Roboto", "Open Sans", "Lato", "Montserrat", "Poppins", "Nunito", "Nunito Sans", "Raleway", "Work Sans", "DM Sans", "Manrope", "Plus Jakarta Sans", "Outfit", "Sora", "Rubik", "Karla", "Mulish", "Barlow", "Barlow Condensed", "IBM Plex Sans", "Source Sans 3", "Noto Sans", "Noto Sans JP", "Noto Sans KR", "Noto Sans Arabic", "Noto Sans Devanagari", "Figtree", "Urbanist", "Space Grotesk", "Archivo", "Public Sans", "Lexend", "Hanken Grotesk", "Red Hat Display", "Albert Sans", "Libre Franklin"],
      "Serif" => ["Source Serif 4", "Playfair Display", "Lora", "Merriweather", "Libre Baskerville", "Cormorant Garamond", "Cormorant", "EB Garamond", "Crimson Pro", "Crimson Text", "DM Serif Display", "DM Serif Text", "Bitter", "Roboto Slab", "Arvo", "Alegreya", "Spectral", "Fraunces", "Bodoni Moda", "Prata", "Noto Serif"],
      "Display" => ["Syne", "Bebas Neue", "Anton", "Oswald", "Archivo Black", "Abril Fatface", "Righteous", "Alfa Slab One", "Cinzel", "Orbitron", "Audiowide", "Russo One", "Teko", "Unbounded", "Bungee", "Chakra Petch", "Yeseva One", "Black Ops One"],
      "Handwriting" => ["Playwrite AR", "Playwrite AR Guides", "Dancing Script", "Pacifico", "Caveat", "Sacramento", "Great Vibes", "Satisfy", "Kalam", "Shadows Into Light", "Indie Flower", "Permanent Marker", "Patrick Hand", "Courgette", "Allura"],
      "Monospace" => ["DM Mono", "IBM Plex Mono", "JetBrains Mono", "Fira Code", "Source Code Pro", "Space Mono", "Roboto Mono", "Inconsolata", "Ubuntu Mono", "PT Mono", "Anonymous Pro", "Cousine", "Share Tech Mono"]
    }.freeze
    ALIASES = {"playwrite argentina guides" => "Playwrite AR Guides", "playwrite argentina" => "Playwrite AR"}.freeze
    def canonical_family(name) = ALIASES.fetch(name.to_s.downcase, name)
    WEIGHTS = {
      "Inter" => "400;500;600;700", "Roboto" => "400;500;700", "Open Sans" => "400;600;700",
      "Barlow" => "400;500;600;700", "Barlow Condensed" => "400;600;700;800;900",
      "Syne" => "400;500;600;700;800", "Source Serif 4" => "400;600;700",
      "DM Mono" => "400;500", "IBM Plex Mono" => "400;500;600;700",
      "Montserrat" => "400;500;600;700", "Poppins" => "400;500;600;700"
    }.freeze
    def families = CATALOG.values.flatten
    def valid_stack?(value)
      value.to_s.length <= 300 && value.to_s.split(",").all? do |part|
        name = part.strip
        name = name[1...-1] if (name.start_with?('"') && name.end_with?('"')) || (name.start_with?("'") && name.end_with?("'"))
        name.match?(/\A[a-zA-Z][a-zA-Z0-9 +\-]*\z/)
      end
    end
    def first_family(value)
      return nil if value.blank? || !valid_stack?(value)
      canonical_family(value.to_s.split(",").first.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'"))
    end
    def google_family(value)
      family = first_family(value)
      family unless family.nil? || SYSTEM.any? { |item| item.casecmp?(family) } || ["Times New Roman", "Courier New", "Trebuchet MS", "Segoe UI", "Apple Color Emoji"].any? { |item| item.casecmp?(family) }
    end
    def stylesheet(values)
      families = Array(values).filter_map { |value| google_family(value) }.uniq.sort
      return nil if families.empty?
      pairs = families.map { |family| ["family", WEIGHTS[family] ? "#{family}:wght@#{WEIGHTS[family]}" : family] }
      "https://fonts.googleapis.com/css2?#{URI.encode_www_form(pairs + [["display", "swap"]])}"
    end
    def css_stack(value, fallback: "sans-serif")
      return nil unless value.present? && valid_stack?(value)
      value.to_s.split(",").map do |part|
        name = part.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
        SYSTEM.any? { |item| item.casecmp?(name) } ? name : canonical_family(name).to_json
      end.join(", ") + ", #{fallback}"
    end
  end
end
