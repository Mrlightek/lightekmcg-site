module Gatekeeper
  module Hosting
    class Deletions
      def self.request!(actor:, node:, confirmation:)
        Access.authorize!(actor, node)
        raise Access::Denied, "Type the exact server name to confirm deletion" unless confirmation.to_s == node.name
        request = nil
        node.with_lock do
          raise Access::Denied, "Server is already deleted" if node.status == "decommissioned"
          raise Access::Denied, "Wait for application setup to finish" if GatekeeperHostedApplication.where(gatekeeper_node: node, status: "provisioning").exists?
          active = GatekeeperOperation.where(gatekeeper_node: node, status: "running", capability: %w[deploy_project deploy_website update_installation create_hosted_application])
          raise Access::Denied, "Wait for the running deployment to finish" if active.exists?
          if !Access.super_admin?(actor)
            raise Access::Denied, "A shared server requires a super administrator to delete it" if
              GatekeeperHostedApplication.where(gatekeeper_node: node).where.not(owner: actor).where.not(status: "deleted").exists? ||
              GatekeeperInstallation.where(gatekeeper_node: node).where.not(account_id: [nil, actor.id]).exists?
          end
          request = ProvisioningRequest.where(gatekeeper_node: node).order(:id).last
          provider = node.compute_provider || request&.compute_provider
          raise Access::Denied, "Server has no cloud provider/resource binding" unless provider && node.provider_resource_id.present?
          request ||= ProvisioningRequest.create!(owner: node.owner, gatekeeper_node: node,
            compute_provider: provider, approval_status: "approved", execution_status: "succeeded", requested_node_count: 1)
          raise Access::Denied, "Provider binding does not match the server" unless request.compute_provider_id == provider.id
          request.update!(destroy_approval_status: "approved", destroy_approved_by: actor.email_address, destroy_approved_at: Time.current,
            metadata: request.metadata.to_h.merge("delete_actor_id" => actor.id, "delete_binding" => binding(node, provider), "delete_state" => "queued"))
          ids = GatekeeperInstallation.where(gatekeeper_node: node).select(:id)
          GatekeeperUpdateTarget.where(gatekeeper_installation_id: ids, status: %w[pending reserved queued failed]).update_all(status: "canceled")
          node.update!(status: "deleting")
        end
        DeleteServerJob.perform_later(request.id, actor.id)
        request
      end

      def self.binding(node, provider)
        {"resource_id" => node.provider_resource_id.to_s, "provider_id" => node.compute_provider_id || provider.id,
          "owner_id" => node.owner_id, "owner_type" => node.owner_type}
      end

      def self.execute!(request:, actor:)
        node = request.gatekeeper_node
        Access.authorize!(actor, node)
        raise Access::Denied, "Deletion approval identity changed" unless request.metadata.to_h["delete_actor_id"] == actor.id &&
          request.metadata.to_h["delete_binding"] == binding(node, request.compute_provider)
        Compute::DeprovisioningService.call(request: request, requested_by: actor.email_address, expected_binding: request.metadata.fetch("delete_binding"))
      end
    end
  end
end
