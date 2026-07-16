# frozen_string_literal: true
module Marlon
  # THE GATE — this runs INSIDE a customer instance.
  #
  # The image ships all the code; this decides what's on. Reads the manifest from
  # MARLON_MANIFEST (raw JSON) or MARLON_MANIFEST_PATH (a file). With neither —
  # e.g. LightekMCG's own app — everything is enabled.
  #
  #   Marlon::Capabilities.enabled?(:billing)   # pack on?
  #   Marlon::Capabilities.feature?(:invoicing) # feature on?
  #   Marlon::Capabilities.mode                 # paid | trial | demo | free
  module Capabilities
    module_function

    def manifest
      return @manifest if defined?(@manifest) && @manifest

      @manifest = load_manifest || {}
    end

    def reload!
      @manifest = nil
      manifest
    end

    # No manifest => the mothership (or dev). Everything on.
    def unrestricted?
      manifest.empty?
    end

    def packs
      Array(manifest["packs"]).map(&:to_s)
    end

    def features
      Array(manifest["features"]).map(&:to_s)
    end

    def enabled?(pack)
      return true if unrestricted?
      packs.include?(pack.to_s)
    end

    def feature?(key)
      return true if unrestricted?
      features.include?(key.to_s)
    end

    def mode
      manifest["mode"] || "unrestricted"
    end

    def instance_id
      manifest["instance_id"]
    end

    def project_type
      manifest["project_type"]
    end

    def usage_billing?
      !!manifest.dig("billing", "usage_billing")
    end

    def load_manifest
      raw = ENV["MARLON_MANIFEST"].presence
      if raw.nil? && (path = ENV["MARLON_MANIFEST_PATH"].presence) && File.exist?(path)
        raw = File.read(path)
      end
      return nil if raw.nil?

      JSON.parse(raw)
    rescue StandardError => e
      Rails.logger.error "[capabilities] manifest unreadable: #{e.message}" if defined?(Rails)
      nil
    end
  end
end
