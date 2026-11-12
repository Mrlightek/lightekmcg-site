module LightekSessions
  # Media activation may register the central app without making it fleet-update eligible.
  class MediaSetup
    def self.installations(site:, actor:)
      GatekeeperInstallation.where(domain:site.host,component:'lightek_app',account:site.tenant,
        gatekeeper_node_id:Gatekeeper::Hosting::Access.nodes(actor).select(:id)).where(adapter:%w[native_rails docker_compose])
    end

    def self.projects(site:, actor:)
      GatekeeperProject.where(domain:site.host,gatekeeper_node_id:Gatekeeper::Hosting::Access.nodes(actor).select(:id))
    end

    def self.connect!(site:, actor:, project_id:)
      project=projects(site:site,actor:actor).find(project_id)
      node=project.gatekeeper_node
      Gatekeeper::Hosting::Access.authorize!(actor,node)
      Gatekeeper::Hosting::Access.active!(node)
      node.with_lock do
        installation=GatekeeperInstallation.find_or_initialize_by(gatekeeper_node:node,domain:site.host,component:'lightek_app')
        if installation.persisted?
          raise ArgumentError,'This runtime belongs to another account.' unless installation.account==site.tenant
          return installation
        end
        resolved=Gatekeeper::Hosting::Runtime.resolve(project)
        raise ArgumentError,'The runtime hostname does not match this website.' unless resolved.domain==site.host
        installation.assign_attributes(account:site.tenant,gatekeeper_project:project,adapter:resolved.adapter,
          repository:project.repository,deployment_config:resolved.deployment_config,current_version:project.deployed_sha)
        installation.save!
        installation
      end
    end
  end
end
