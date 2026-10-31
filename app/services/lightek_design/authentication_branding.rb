# frozen_string_literal: true
module LightekDesign
  class AuthenticationBranding
    TEXT_KEYS = %w[headline description eyebrow].freeze
    COLORS = %w[color_bg color_text color_primary color_text_muted].freeze
    FONTS = %w[font_sans font_heading].freeze
    attr_reader :site
    def initialize(site)
      @site = site
    end
    def self.for_host(host)
      new(DymondSite::Site.find_by(host: host.to_s.downcase))
    end
    def settings = site&.manifest.to_h.fetch("authentication_branding", {}).to_h
    def tokens = site&.active_template&.settings.to_h.fetch("tokens", {}).to_h
    def name = site&.name.presence || "Lightek"
    def platform? = site.nil? || %w[lightekmcg.com www.lightekmcg.com].include?(site.host.to_s)
    def text(key) = settings[key].to_s.presence
    def color(key)
      value = tokens[key].to_s
      return value if value.match?(/\A#[0-9a-f]{6}\z/i)
      return "#" + value.delete_prefix("#").chars.map { |char| char * 2 }.join if value.match?(/\A#[0-9a-f]{3}\z/i)
      {"color_bg" => "#07070a", "color_text" => "#f7f5ef", "color_primary" => "#eab04d", "color_text_muted" => "#aaa6a0"}.fetch(key)
    end
    def font(key)
      Fonts.css_stack(tokens[key], fallback: key == "font_heading" ? "serif" : "sans-serif") || (key == "font_heading" ? "Georgia, serif" : "system-ui, sans-serif")
    end
    def self.safe_image_url(value)
      value = value.to_s
      return if value.blank? || value.match?(/[\s"'<>\\()]/)
      uri = URI.parse(value)
      value if (value.start_with?("/") && !value.start_with?("//") && !uri.host) || (uri.scheme == "https" && uri.host.present? && !uri.userinfo)
    rescue URI::InvalidURIError
      nil
    end
    def logo_url
      self.class.safe_image_url(DymondCompute::Storage.url_for(site&.active_template&.settings.to_h["logo_asset_id"]))
    end
    def background_url = self.class.safe_image_url(settings["background_url"])
    def blend(a, b, weight)
      x = a.delete_prefix("#").scan(/../).map { |n| n.to_i(16) }
      y = b.delete_prefix("#").scan(/../).map { |n| n.to_i(16) }
      "#" + x.zip(y).map { |left, right| "%02x" % (left * (1 - weight) + right * weight).round }.join
    end
    def accent_rgb = color("color_primary").delete_prefix("#").scan(/../).map { |n| n.to_i(16) }.join(",")
    def button_text
      components = color("color_primary").delete_prefix("#").scan(/../).map { |n| n.to_i(16) / 255.0 }.map { |n| n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055)**2.4 }
      luminance = components.zip([0.2126, 0.7152, 0.0722]).sum { |component, weight| component * weight }
      luminance > 0.179 ? "#080808" : "#ffffff"
    end
    def self.save!(site:, values:, logo: nil, background: nil)
      values = values.to_h.stringify_keys
      TEXT_KEYS.each { |key| raise ArgumentError, "Keep #{key.humanize.downcase} under #{key == 'description' ? 400 : 120} characters." if values[key].to_s.length > (key == "description" ? 400 : 120) }
      supplied = values.slice(*(COLORS + FONTS)).transform_values { |value| value.to_s.strip }
      supplied.each { |key, value| raise ArgumentError, "Choose a valid color." if COLORS.include?(key) && value.present? && !value.match?(/\A#[0-9a-f]{6}\z/i) }
      supplied.each { |key, value| raise ArgumentError, "Choose a valid font family." if FONTS.include?(key) && value.present? && !Fonts.valid_stack?(value) }
      uploads = {"logo_url" => logo, "background_url" => background}.compact
      uploads.each_value do |file|
        raise ArgumentError, "Choose a PNG, JPEG, GIF or WebP image up to 10 MB." unless file.respond_to?(:tempfile) && file.size.between?(1, 10.megabytes) && %w[image/png image/jpeg image/gif image/webp].include?(Marcel::MimeType.for(file.tempfile, name: file.original_filename))
        file.tempfile.rewind
      end
      images = uploads.transform_values do |file|
        asset = DymondCompute::Storage.ingest(file)
        {"id" => asset.id, "url" => safe_image_url(asset.url) || raise(ArgumentError, "The uploaded image URL is unavailable.")}
      end
      site.with_lock do
        manifest = site.manifest.to_h.deep_dup
        branding = manifest.fetch("authentication_branding", {}).merge(values.slice(*TEXT_KEYS).transform_values { |value| value.to_s.strip }).merge(images.slice("background_url").transform_values { |image| image.fetch("url") })
        branding.delete("background_url") if values["remove_background"] == "1"
        manifest["authentication_branding"] = branding
        template = site.active_template
        if images.key?("logo_url") || values["remove_logo"] == "1" || supplied.any? { |key, value| value != template&.settings.to_h.dig("tokens", key).to_s }
          if !template || template.settings["lightek_site_id"].to_s != site.id.to_s || DymondSite::Site.where(active_template_id: template.id).where.not(id: site.id).exists?
            template = DymondSite::SiteTemplate.create!(name: "#{site.name} appearance", key: "lightek_site_#{site.id}_appearance_#{SecureRandom.hex(6)}", preset: false,
              settings: (template&.settings.to_h || {}).merge("lightek_site_id" => site.id))
          end
          appearance = template.settings.merge("tokens" => template.settings.fetch("tokens", {}).merge(supplied))
          appearance["logo_asset_id"] = images.fetch("logo_url").fetch("id") if images.key?("logo_url")
          appearance.delete("logo_asset_id") if values["remove_logo"] == "1"
          template.update!(settings: appearance)
        end
        site.update!(manifest: manifest, active_template: template)
      end
      site
    end
  end
end
