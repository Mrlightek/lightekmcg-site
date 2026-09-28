module Studio
  class Credentials
    class ConfigurationError < StandardError; end

    def self.checkout!(slug:, consumer:, purpose:)
      new.checkout!(slug:, consumer:, purpose:)
    end

    def checkout!(slug:, consumer:, purpose:)
      if defined?(LightekVault::Service)
        return LightekVault::Service.checkout!(
          slug: slug,
          consumer: consumer,
          purpose: purpose,
          requested_by: "lightek-studio"
        )
      end

      raise ConfigurationError, "Lightek Vault is required for Studio credentials" if Rails.env.production?

      development_payload(slug)
    end

    private

    def development_payload(slug)
      prefix = slug.upcase.tr("-", "_")
      ENV.each_with_object({}) do |(key, value), payload|
        next unless key.start_with?("#{prefix}__")

        payload[key.delete_prefix("#{prefix}__").downcase] = value
      end
    end
  end
end
