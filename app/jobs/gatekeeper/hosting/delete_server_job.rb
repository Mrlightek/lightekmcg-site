module Gatekeeper
  module Hosting
    class DeleteServerJob < ApplicationJob
      queue_as :default
      def perform(request_id, actor_id)
        request = ProvisioningRequest.find(request_id)
        Deletions.execute!(request: request, actor: User.find(actor_id))
      rescue StandardError => error
        if request
          request.update!(metadata: request.metadata.to_h.merge("delete_state" => "failed", "delete_error" => "Deletion failed (#{error.class}). Review and retry."))
          node = request.gatekeeper_node
          if node && !request.destroyed_at && request.metadata.to_h["delete_binding"] == Deletions.binding(node, request.compute_provider)
            node.update!(status: "delete_failed")
          end
        end
        Rails.logger.error("[Server deletion] request=#{request_id} error=#{error.class}")
      end
    end
  end
end
