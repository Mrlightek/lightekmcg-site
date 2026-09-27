module Gatekeeper
  module Compute
    class NodeVerificationService
      class VerificationFailed < StandardError; end

      def self.call(request:, requested_by:)
        node = request.gatekeeper_node ||
          raise(VerificationFailed, "Provisioning request has no GatekeeperNode")

        adapter = request.compute_provider.adapter(requested_by: requested_by)
        provider_node = adapter.node(node.provider_resource_id)

        provider_status = provider_node["status"].to_s
        ipv4 = Array(provider_node["ipv4"]).first

        status =
          case provider_status
          when "running" then "healthy"
          when "offline" then "degraded"
          when "provisioning", "booting" then "provisioning"
          else "unknown"
          end

        node.update!(
          ip_address: ipv4.presence || node.ip_address,
          public_ipv6: provider_node["ipv6"].to_s.split("/").first.presence || node.public_ipv6,
          status: status,
          last_healthcheck_at: Time.current,
          metadata: node.metadata.to_h.merge(
            "provider_status" => provider_status,
            "provider_verified_at" => Time.current.iso8601
          )
        )

        {
          node_id: node.id,
          provider_resource_id: node.provider_resource_id,
          provider_status: provider_status,
          gatekeeper_status: node.status,
          ipv4: node.ip_address,
          ipv6: node.public_ipv6
        }
      end
    end
  end
end
