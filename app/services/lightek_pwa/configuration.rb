# frozen_string_literal: true
module LightekPwa
  # Global registries supply templates; per-site overrides never mutate them.
  class Configuration
    CONFIGURABLE_MODULES = {
      "home" => %w[hero-live following live-now communities trending-clips creator-discovery],
      "watch" => %w[featured-broadcast guide live-channels originals documentaries],
      "explore" => %w[people communities programs],
      "communities" => %w[your-communities discover-communities]
    }.freeze
    def initialize(site)
      @site = site
      @app = Application.find_by(site_id: site&.id) || Application.new(site: site)
    end
    attr_reader :app
    def surfaces
      Surface.ordered.includes(:modules).filter_map do |surface|
        override = app.settings.fetch("surfaces", {}).fetch(surface.key, {})
        next if override.fetch("enabled", surface.enabled) == false
        payload = surface.bootstrap_payload
        payload[:label] = override["label"].presence || payload[:label]
        payload[:position] = override.fetch("position", payload[:position]).to_i
        payload[:configuration] = payload[:configuration].merge("heading" => override["heading"], "intro" => override["intro"], "layout_configured" => override.key?("modules"))
        payload[:modules] = surface.modules.filter_map do |record|
          mod = record.bootstrap_payload
          setting = override.fetch("modules", {}).fetch(record.key, {})
          next if setting.fetch("enabled", record.enabled) == false
          mod.merge(label: setting["label"].presence || mod[:label], position: setting.fetch("position", mod[:position]).to_i, configuration: mod[:configuration].merge("post_ids" => setting.fetch("post_ids", [])))
        end.sort_by { |mod| mod[:position] }
        payload
      end.sort_by { |surface| surface[:position] }
    end
    def navigation
      allowed = surfaces.map { |surface| surface[:key] }
      defaults = NavigationItem.ordered.map(&:bootstrap_payload).index_by { |item| item[:key] }
      app.settings.fetch("navigation", {}).each do |key, item|
        defaults[key] = defaults.fetch(key, {key: key, href: "#/home", surface_id: "home", placement: "primary", position: 100}).merge(item.symbolize_keys)
      end
      defaults.values.select { |item| item[:enabled] != false && (item[:surface_id].blank? || allowed.include?(item[:surface_id])) }.sort_by { |item| item[:position].to_i }
    end
    def manifest
      brand = app.bootstrap_payload
      {id: "/lightek/", name: brand[:name], short_name: brand[:short_name], description: brand[:description],
        start_url: "/lightek/index.html#/" + app.start_surface, scope: "/lightek/", display: "standalone",
        theme_color: app.theme_color, background_color: app.background_color,
        icons: app.icon.attached? ? [{src: app.image_path(:icon), sizes: "any", type: app.icon.blob.content_type, purpose: "any"}] :
          [192, 512].map { |size| {src: "/lightek/icons/icon-#{size}.png", sizes: "#{size}x#{size}", type: "image/png"} }}
    end
  end
end
