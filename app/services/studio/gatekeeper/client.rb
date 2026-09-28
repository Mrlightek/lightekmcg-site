module Studio
  module Gatekeeper
    class AuthorizationError < StandardError; end
    class ConfigurationError < StandardError; end

    class Client
      def self.authorize!(capability:, subject:, context: {})
        new.authorize!(capability:, subject:, context:)
      end

      def authorize!(capability:, subject:, context: {})
        if defined?(::Gatekeeper) && ::Gatekeeper.respond_to?(:authorize_capability!)
          return ::Gatekeeper.authorize_capability!(
            capability: capability,
            subject: subject,
            context: context
          )
        end

        return local_authorization(capability:, subject:, context:) if local_mode?

        raise ConfigurationError,
              "Gatekeeper integration is required. Set STUDIO_GATEKEEPER_MODE=local only for local development."
      end

      private

      def local_mode?
        !Rails.env.production? && ENV.fetch("STUDIO_GATEKEEPER_MODE", "local") == "local"
      end

      def local_authorization(capability:, subject:, context:)
        Rails.logger.info(
          "[Studio::Gatekeeper] local authorization capability=#{capability} " \
          "subject=#{subject.class.name}:#{subject.id} context=#{context.inspect}"
        )
        true
      end
    end
  end
end
