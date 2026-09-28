module Studio
  module Operations
    class Dispatcher
      def initialize(operation)
        @operation = operation
      end

      def call
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

        provider_class = Studio::Providers::Registry.fetch(operation.provider)
        provider_class.new(operation).call
      end

      private

      attr_reader :operation
    end
  end
end
