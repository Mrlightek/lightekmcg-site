module Gatekeeper
  module Compute
    class DeprovisioningService
      class NotApproved < StandardError; end
      class UnsupportedProvider < StandardError; end

      def self.call(request:, requested_by:)
        new(request:, requested_by:).call
      end

      def initialize(request:, requested_by:)
        @request = request
        @requested_by = requested_by.to_s
      end

      def call
        raise NotApproved, "Destruction requires explicit approval" unless request.destroy_approval_status == "approved"

        node = request.gatekeeper_node ||
          raise(NotApproved, "No GatekeeperNode is attached")

        raise UnsupportedProvider, "First destroy pass supports Linode only" unless request.compute_provider&.slug == "linode"

        operation = GatekeeperOperation.create!(
          gatekeeper_node: node,
          capability: "destroy_compute_node",
          requested_by: requested_by,
          status: "running",
          parameters: {
            provisioning_request_id: request.id,
            provider: request.compute_provider.slug,
            provider_resource_id: node.provider_resource_id
          },
          started_at: Time.current
        )

        begin
          adapter = request.compute_provider.adapter(
            requested_by: requested_by,
            operation_id: operation.id
          )

          adapter.destroy_node(node.provider_resource_id)

          operation.update!(
            status: "succeeded",
            result: {
              "provider_resource_id" => node.provider_resource_id,
              "destroyed" => true
            },
            exit_status: 0,
            completed_at: Time.current
          )

          node.update!(
            status: "decommissioned",
            metadata: node.metadata.to_h.merge(
              "destroyed_at" => Time.current.iso8601,
              "destroyed_by" => requested_by
            )
          )

          request.update!(
            destroyed_at: Time.current,
            metadata: request.metadata.to_h.merge(
              "deprovision_operation_id" => operation.id
            )
          )

          true
        rescue StandardError => e
          operation.update!(
            status: "failed",
            error_class: e.class.name,
            error_message: e.message,
            exit_status: 1,
            completed_at: Time.current
          )
          raise
        end
      end

      private

      attr_reader :request, :requested_by
    end
  end
end
