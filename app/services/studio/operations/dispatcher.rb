module Studio
  module Operations
    class Dispatcher
      def initialize(operation)
        @operation = operation
      end

      def call
        unless nevaeh_authorized?
          Studio::Gatekeeper::Client.authorize!(
            capability: operation.capability,
            subject: operation,
            context: {
              project_id: operation.studio_project_id,
              production_id: operation.production_id,
              scene_id: operation.studio_scene_id,
              provider: operation.provider,
              operation_type: operation.operation_type
            }.compact
          )
        end

        provider_class = Studio::Providers::Registry.fetch(operation.provider)
        provider_class.new(operation).call
      end

      private

      def nevaeh_authorized?
        orchestration =
          operation
            .metadata
            .to_h
            .fetch("orchestration", {})
            .to_h

        orchestration["managed_by"] == "nevaeh" &&
          orchestration["authorized"] == true &&
          orchestration["correlation_id"].present?
      end

      attr_reader :operation
    end
  end
end
