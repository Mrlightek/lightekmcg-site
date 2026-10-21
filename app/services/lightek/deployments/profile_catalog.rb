# Frozen, data-only deployment profile catalog. Does not provision or seed a tenant.
require "yaml"

module Lightek
  module Deployments
    class ProfileCatalog
      ROOT = Rails.root.join("config/lightek/deployment_profiles").freeze
      AVAILABLE = %w[business media].freeze
      REQUIRED_MODULES = %w[cms contact billing community studio streaming].freeze
      REQUIRED_CLIENTS = %w[web ios tvos android_flutter roku].freeze

      def self.fetch(name)
        key = name.to_s
        raise ArgumentError, "unknown deployment profile" unless AVAILABLE.include?(key)

        raw = YAML.safe_load_file(ROOT.join("#{key}.yml"), aliases: false)
        validate!(raw, key)
        raw.deep_dup
      end

      def self.validate!(data, expected_name)
        raise ArgumentError, "invalid profile" unless data.is_a?(Hash)
        raise ArgumentError, "invalid profile version" unless data["schema_version"] == 1
        raise ArgumentError, "invalid profile identity" unless data["profile"] == expected_name && data["product"] == "lightek-site"
        raise ArgumentError, "profile must be customer isolated" unless data["mode"] == "customer_isolated"

        security = data.fetch("security")
        raise ArgumentError, "insecure profile" unless security["customer_data_isolated"] == true &&
          security["inherit_corporate_knowledge"] == false &&
          security["inherit_platform_secrets"] == false &&
          security["admin_invite_required"] == true

        REQUIRED_MODULES.each { |key| raise ArgumentError, "invalid module flag" unless [true, false].include?(data.fetch("modules").fetch(key)) }
        REQUIRED_CLIENTS.each { |key| raise ArgumentError, "invalid client flag" unless [true, false].include?(data.fetch("clients").fetch(key)) }
        raise ArgumentError, "web client required" unless data["clients"]["web"] == true

        pages = data.fetch("defaults").fetch("pages")
        raise ArgumentError, "default pages missing" unless pages.is_a?(Array) && pages.any? { |p| p["slug"] == "home" }
        raise ArgumentError, "duplicate page slugs" unless pages.map { |p| p.fetch("slug") }.uniq.length == pages.length
        true
      end
    end
  end
end
