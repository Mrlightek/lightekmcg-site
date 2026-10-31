module Gatekeeper
  module Compute
    class DeprovisioningService
      class NotApproved < StandardError; end
      class UnsupportedProvider < StandardError; end

      def self.call(request:, requested_by:, expected_binding: nil)
        raise NotApproved, "Destruction requires explicit approval" unless request.destroy_approval_status == "approved"
        node = request.gatekeeper_node || raise(NotApproved, "No Gatekeeper node is attached")
        raise UnsupportedProvider, "No provider/resource is bound" unless request.compute_provider && node.provider_resource_id.present?
        operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: "destroy_compute_node",
          requested_by: requested_by.to_s, status: "queued",
          parameters: {provisioning_request_id: request.id, provider: request.compute_provider.slug, provider_resource_id: node.provider_resource_id})
        failure = nil
        node.with_lock do
          request.reload
          if request.destroy_approval_status != "approved" || (expected_binding && expected_binding != Gatekeeper::Hosting::Deletions.binding(node, request.compute_provider))
            failure = NotApproved.new("Deletion approval or provider binding changed")
            operation.update!(status: "failed", error_class: failure.class.name, error_message: failure.message, completed_at: Time.current)
            next
          end
          if request.destroyed_at || node.status == "decommissioned"
            operation.update!(status: "succeeded", exit_status: 0, result: {destroyed: true, already_destroyed: true}, completed_at: Time.current)
          else
            begin
              operation.update!(status: "running", started_at: Time.current)
              adapter = request.compute_provider.adapter(requested_by: requested_by.to_s, operation_id: operation.id)
              result = adapter.destroy_node(node.provider_resource_id)
              raise UnsupportedProvider, "Provider did not accept deletion" if result == false
              now = Time.current
              node.update!(status: "decommissioned", metadata: node.metadata.to_h.merge("destroyed_at" => now.iso8601, "destroyed_by" => requested_by.to_s))
              request.update!(destroyed_at: now, metadata: request.metadata.to_h.merge("deprovision_operation_id" => operation.id, "delete_state" => "destroyed"))
              GatekeeperInstallation.where(gatekeeper_node: node).update_all(enabled: false, automatic_updates: false)
              GatekeeperHostedApplication.where(gatekeeper_node: node).update_all(status: "deleted")
              operation.update!(status: "succeeded", exit_status: 0, completed_at: now,
                result: {provider_resource_id: node.provider_resource_id, destroyed: true})
            rescue StandardError => error
              failure = error
              node.update!(status: "delete_failed")
              operation.update!(status: "failed", error_class: error.class.name,
                error_message: "Provider deletion failed; review operation and retry.", exit_status: 1, completed_at: Time.current)
            end
          end
        end
        raise failure if failure
        true
      end
    end
  end
end
