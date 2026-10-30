# frozen_string_literal: true

module Gatekeeper
  module Compute
    class DeletedNodeReconciliation
      class Uncertain < StandardError; end

      def self.call!(request:, requested_by:)
        node = request.reload.gatekeeper_node
        return false unless node

        adapter = request.compute_provider.adapter(requested_by: requested_by)
        begin
          adapter.node(node.provider_resource_id)
          return false
        rescue StandardError => e
          raise unless e.message.start_with?("Provider HTTP 404:")
        end

        matches = ProvisioningExecutionService.matching_provider_nodes(adapter.nodes, request)
        raise Uncertain, "Matching cloud instance still exists" if matches.any?

        request.with_lock do
          request.reload
          raise Uncertain, "Node reference changed" unless request.gatekeeper_node_id == node.id

          old = request.metadata.to_h
          history = Array(old["retired_provider_nodes"])
          history << { "node_id" => node.id, "resource_id" => node.provider_resource_id,
                       "ip" => node.ip_address, "confirmed_absent_at" => Time.current.iso8601 }
          node.update!(status: "decommissioned", metadata: node.metadata.to_h.merge("provider_status" => "deleted"))
          request.update!(gatekeeper_node: nil, execution_status: "awaiting_approval",
                          provisioned_at: nil,
                          metadata: old.except("provider_resource_id", "allocation_attempted",
                                               "node_credential_secret_slug")
                                       .merge("retired_provider_nodes" => history))
        end
        true
      end
    end
  end
end
