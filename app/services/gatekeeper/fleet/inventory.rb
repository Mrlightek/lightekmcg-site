module Gatekeeper
  module Fleet
    class Inventory
      # Both the paid-instance installer and the standalone website installer register nodes.
      def self.sync!
        GatekeeperNode.find_each { |node| sync_node!(node) }
      end

      def self.sync_node!(node)
        return if node.local? || %w[decommissioned deleting delete_failed].include?(node.status)
        metadata = node.metadata.to_h
        node.gatekeeper_projects.find_each do |project|
          profile = project.metadata.to_h.fetch("fleet_deployment", {})
          adapter = profile.fetch("adapter", "native_rails")
          component = profile.fetch("component", "lightek_app")
          next if component == "lightek_app" && (metadata["role"] == "production" || metadata["local_node"])
          installation = GatekeeperInstallation.find_or_initialize_by(gatekeeper_node: node, domain: project.domain, component: component)
          raise ArgumentError, "Installation #{project.domain} belongs to another node" if installation.persisted? && installation.gatekeeper_node_id != node.id
          if installation.new_record? || installation.gatekeeper_project_id.nil?
            config = if adapter == "native_rails"
              {"app_root" => project.app_root, "app_user" => project.app_user,
                "env_file" => "/etc/lightek/#{project.name}.env",
                "ruby_bin" => "/home/#{project.app_user}/.rbenv/versions/#{project.ruby_version}/bin",
                "worker_mode" => "systemd", "worker_service" => project.sidekiq_service,
                "health_url" => project.health_url, "revision_url" => "https://#{project.domain}/__lightek/release"}
            else
              {}
            end
            installation.assign_attributes(gatekeeper_node: node, gatekeeper_project: project,
              adapter: adapter, repository: project.repository, deployment_config: config.merge(profile.fetch("config", {})))
            installation.current_version ||= project.deployed_sha
          end
          installation.account_id ||= node.owner_id if node.owner_type == "User"
          installation.save!
        end
        receipt = metadata.fetch("website_deployment", {})
        return if metadata["role"] == "production" || metadata["local_node"]
        domains = metadata.fetch("website_deployments", {}).keys
        url = receipt["url"].to_s
        domains << url.delete_prefix("https://").delete_suffix("/") if url.start_with?("https://")
        domains.uniq.each do |domain|
          installation = GatekeeperInstallation.find_or_initialize_by(gatekeeper_node: node, domain: domain, component: "lightek_app")
          raise ArgumentError, "Installation #{domain} is already bound to another node" if installation.persisted? && installation.gatekeeper_node_id != node.id
          installation.gatekeeper_node = node
          config = metadata.fetch("website_deployments", {}).fetch(domain, {})
          if installation.new_record?
            # Website metadata alone does not imply that Rails runs in Docker.
            installation.adapter = config.fetch("deployment_adapter", "native_rails")
            installation.deployment_config = config.fetch("fleet_config", {})
            installation.account_id = config["owner_id"]
          end
          installation.current_version ||= receipt["release"] if url == "https://#{domain}"
          installation.save!
        end
      end
    end
  end
end
