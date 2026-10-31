module Gatekeeper
  module Hosting
    class Runtime
      def self.resolve(project)
        installation = GatekeeperInstallation.find_by(gatekeeper_project_id: project.id)
        unless installation
          profile = project.metadata.to_h.fetch("fleet_deployment", {})
          home = project.app_user == "root" ? "/root" : "/home/#{project.app_user}"
          config = {"app_root" => project.app_root, "app_user" => project.app_user,
            "env_file" => "/etc/lightek/#{project.name}.env", "ruby_bin" => "#{home}/.rbenv/versions/#{project.ruby_version}/bin",
            "worker_mode" => "systemd", "worker_service" => project.sidekiq_service,
            "health_url" => project.health_url, "revision_url" => "https://#{project.domain}/__lightek/release"}
          installation = GatekeeperInstallation.new(gatekeeper_node_id: project.gatekeeper_node_id, domain: project.domain,
            gatekeeper_project: project, adapter: profile.fetch("adapter", "native_rails"),
            deployment_config: config.merge(profile.fetch("config", {})))
        end
        raise Access::Denied, "Select a configured native Rails runtime" unless installation.adapter == "native_rails" && installation.configured?
        installation
      end
    end
  end
end
