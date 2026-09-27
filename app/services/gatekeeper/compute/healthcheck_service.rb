module Gatekeeper
  module Compute
    class HealthcheckService
      def self.call(provider:, requested_by:)
        result = Registry.build(provider, requested_by:).healthcheck
        provider.mark_health!(status: result[:ok] ? "healthy" : "degraded", metadata: result.stringify_keys)
        result
      rescue StandardError => e
        provider.mark_health!(status: "failed", metadata: { "error_class" => e.class.name, "error_message" => e.message })
        raise
      end
    end
  end
end
