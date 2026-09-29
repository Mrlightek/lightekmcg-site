# frozen_string_literal: true

module Studio
  module Billing
    class Pricing
      class ConfigurationError < StandardError; end

      DEVELOPMENT_DEFAULTS = {
        "build_scene" => 500
      }.freeze

      ENV_KEYS = {
        "build_scene" => "STUDIO_BUILD_SCENE_PRICE_CENTS"
      }.freeze

      def self.principal_cents_for(operation_type)
        operation_type = operation_type.to_s

        env_key = ENV_KEYS.fetch(operation_type) do
          raise ConfigurationError,
                "No Studio pricing configuration exists for #{operation_type.inspect}"
        end

        raw =
          if ENV.key?(env_key)
            ENV.fetch(env_key)
          elsif Rails.env.production?
            raise ConfigurationError,
                  "#{env_key} must be configured in production"
          else
            DEVELOPMENT_DEFAULTS.fetch(operation_type)
          end

        cents = Integer(raw)

        unless cents.positive?
          raise ConfigurationError,
                "#{env_key} must be greater than zero"
        end

        cents
      rescue ArgumentError, TypeError
        raise ConfigurationError,
              "#{env_key} must contain an integer number of cents"
      end
    end
  end
end
