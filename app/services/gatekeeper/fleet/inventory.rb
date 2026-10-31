module Gatekeeper
  module Fleet
    class Inventory
      # Both the paid-instance installer and the standalone website installer register nodes.
      def self.sync!
        GatekeeperNode.find_each { |node| sync_node!(node) }
      end

      def self.sync_node!(node)
        return if node.local? || node.status == "decommissioned" || node.metadata.to_h["role"] == "production" || node.metadata.to_h["local_node"]
        metadata = node.metadata.to_h
        receipt = metadata.fetch("website_deployment", {})
        domains = metadata.fetch("website_deployments", {}).keys
        url = receipt["url"].to_s
        domains << url.delete_prefix("https://").delete_suffix("/") if url.start_with?("https://")
        domains.uniq.each do |domain|
          installation = GatekeeperInstallation.find_or_initialize_by(domain: domain)
          raise ArgumentError, "Installation #{domain} is already bound to another node" if installation.persisted? && installation.gatekeeper_node_id != node.id
          installation.gatekeeper_node = node
          installation.current_version ||= receipt["release"] if url == "https://#{domain}"
          installation.save!
        end
      end
    end
  end
end
