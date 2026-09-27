module Gatekeeper
  module Compute
    class ProviderValidationService
      READ_ONLY_CAPABILITIES = %w[regions plans images nodes].freeze

      def self.call(provider:, requested_by:)
        new(provider:, requested_by:).call
      end

      def initialize(provider:, requested_by:)
        @provider = provider
        @requested_by = requested_by
      end

      def call
        provider.update!(status: "validating")

        adapter = provider.adapter(requested_by: requested_by)
        checks = {}

        health = adapter.healthcheck
        checks["healthcheck"] = { "passed" => health[:ok] == true, "result" => health.stringify_keys }

        READ_ONLY_CAPABILITIES.each do |capability|
          next unless provider.capability?(capability)

          begin
            result = adapter.public_send(capability)
            checks[capability] = {
              "passed" => true,
              "count" => result.respond_to?(:count) ? result.count : nil
            }.compact
          rescue StandardError => e
            checks[capability] = {
              "passed" => false,
              "error_class" => e.class.name,
              "error_message" => e.message
            }
          end
        end

        passed = checks.values.all? { |check| check["passed"] == true }

        provider.update!(
          health_status: passed ? "healthy" : "degraded",
          last_healthcheck_at: Time.current,
          metadata: provider.metadata.to_h.merge(
            "validation_status" => passed ? "passed" : "failed",
            "validation_checks" => checks,
            "validated_at" => Time.current.iso8601
          )
        )

        checks
      rescue StandardError => e
        provider.update!(
          health_status: "failed",
          last_healthcheck_at: Time.current,
          metadata: provider.metadata.to_h.merge(
            "validation_status" => "failed",
            "validation_error" => "#{e.class}: #{e.message}"
          )
        )
        raise
      end

      private

      attr_reader :provider, :requested_by
    end
  end
end
