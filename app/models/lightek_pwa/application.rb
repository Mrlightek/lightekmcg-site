# frozen_string_literal: true
module LightekPwa
  class Application < ApplicationRecord
    self.table_name = "lightek_pwa_applications"
    SURFACES = %w[home watch clips explore communities messages create space money susu studio].freeze
    belongs_to :site, class_name: "DymondSite::Site"
    has_one_attached :logo
    has_one_attached :icon
    validates :site_id, uniqueness: true
    validates :name, length: {maximum: 100}
    validates :short_name, length: {maximum: 24}
    validates :description, :welcome_message, length: {maximum: 3000}
    validates :support_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
    validates :theme_color, :background_color, format: {with: /\A#[0-9a-fA-F]{6}\z/}
    validates :status, inclusion: {in: %w[published maintenance]}
    validates :start_surface, inclusion: {in: SURFACES}
    validate :valid_settings
    validate :valid_images

    def display_name = name.presence || site.name.presence || "Lightek"
    def surface_enabled?(key)
      key = "money" if key == "susu"
      override = settings.fetch("surfaces", {}).fetch(key, {})
      return override["enabled"] != false if override.key?("enabled")
      Surface.find_by(key: key)&.enabled != false
    end
    def image_path(kind)
      attachment = public_send(kind)
      attachment.attached? ? Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true) : nil
    end
    def bootstrap_payload
      {id: "site-#{site_id}", name: display_name, short_name: short_name.presence || display_name.first(24),
        description: description, theme_color: theme_color, background_color: background_color,
        status: status, start_surface: start_surface, support_email: support_email,
        welcome_message: welcome_message, logo_url: image_path(:logo), icon_url: image_path(:icon),
        manifest_url: "/api/lightek/pwa/manifest"}
    end

    private
    def valid_settings
      unless settings.is_a?(Hash) && settings.to_json.bytesize <= 200_000 && (settings.keys - %w[surfaces navigation]).empty?
        errors.add(:settings, "contains unsupported configuration"); return
      end
      surfaces = settings.fetch("surfaces", {})
      errors.add(:settings, "must have a valid start surface") unless surface_enabled?(start_surface)
      unless surfaces.is_a?(Hash) && (surfaces.keys - SURFACES).empty?
        errors.add(:settings, "contains unsupported surfaces"); return
      end
      surfaces.each_value do |value|
        unless value.is_a?(Hash) && value["label"].to_s.length <= 100 && value.fetch("modules", {}).is_a?(Hash)
          errors.add(:settings, "contains invalid surface settings"); next
        end
        value.fetch("modules", {}).each_value do |mod|
          errors.add(:settings, "contains invalid module settings") unless mod.is_a?(Hash) && mod["label"].to_s.length <= 100
        end
      end
      navigation = settings.fetch("navigation", {})
      unless navigation.is_a?(Hash) && navigation.size <= 40
        errors.add(:settings, "contains invalid navigation"); return
      end
      navigation.each do |key, item|
        unless key.match?(/\A[a-z0-9_-]{1,80}\z/) && item.is_a?(Hash) && item["label"].to_s.length <= 80 &&
            (item["surface_id"].blank? || SURFACES.include?(item["surface_id"])) && %w[primary tools footer].include?(item.fetch("placement", "primary")) && safe_href?(item.fetch("href", "#/home"))
          errors.add(:settings, "contains an invalid navigation link")
        end
      end
    rescue NoMethodError, TypeError
      errors.add(:settings, "contains invalid settings")
    end
    def safe_href?(value)
      return false unless value.is_a?(String) && value.length <= 1000 && !value.match?(/[\x00-\x20\\]/)
      value.match?(/\A#\/[a-zA-Z0-9_\/-]*\z/) || value.match?(/\A\/(?!\/)[^<>"']*\z/) ||
        (URI.parse(value).then { |uri| uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo })
    rescue URI::InvalidURIError
      false
    end
    def valid_images
      [logo, icon].each do |image|
        next unless image.attached?
        errors.add(:base, "Brand images must be PNG, JPEG or WebP, up to 2 MB") unless
          %w[image/png image/jpeg image/webp].include?(image.blob.content_type) && image.blob.byte_size <= 2.megabytes
      end
    end
  end
end
