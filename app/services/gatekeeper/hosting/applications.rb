module Gatekeeper
  module Hosting
    class Applications
      def self.create!(actor:, node:, project:, owner:, name:, domain:)
        Access.authorize!(actor, node)
        raise Access::Denied, "Runtime is not installed on this server" unless project.gatekeeper_node_id == node.id
        raise Access::Denied, "Only super admins may assign another account" unless Access.manages?(actor, owner)
        Runtime.resolve(project)
        begin
          hostname = LightekSettings::SiteDomain.public_hostname!(domain)
        rescue LightekSettings::SiteDomain::Invalid => error
          raise Access::Denied, error.message
        end
        app = nil
        capacity_owner = actor.respond_to?(:white_label?) && actor.white_label? ? actor : owner
        capacity_owner.with_lock do
          node.with_lock do
            Access.active!(node)
            Access.enforce_limit!(actor: actor, owner: owner, additional: 1)
            host = hostname
            raise Access::Denied, "Hostname is already assigned to an application" if GatekeeperProject.exists?(domain: host) || GatekeeperApplicationLaunch.where.not(status: "deleted").exists?(domain: host)
            app = GatekeeperHostedApplication.create!(gatekeeper_node: node, gatekeeper_project: project,
              owner: owner, requested_by: actor, name: name, domain: host)
          end
        end
        ProvisionApplicationJob.perform_later(app.id)
        app
      end

      def self.provision!(app)
        operation = nil
        app.owner.with_lock do
          app.gatekeeper_node.with_lock do
            app.reload
            return if app.status == "ready" || app.status == "deleted" || app.status == "provisioning"
            LightekIdentity::Permissions.application!(app.requested_by,app,"manage")
            Access.active!(app.gatekeeper_node)
            quota_actor = Access.manages?(app.requested_by,app.owner) ? app.requested_by : app.owner
            Access.enforce_limit!(actor: quota_actor, owner: app.owner, additional: 0)
            operation = GatekeeperOperation.create!(gatekeeper_node: app.gatekeeper_node, gatekeeper_project: app.gatekeeper_project,
              capability: "create_hosted_application", requested_by: app.requested_by.email_address,
              status: "running", started_at: Time.current, parameters: {hosted_application_id: app.id, domain: app.domain})
            app.update!(status: "provisioning", started_at: Time.current, gatekeeper_operation: operation, error_message: nil)
          end
        end
        runtime = Runtime.resolve(app.gatekeeper_project)
        Dns.prepare!(domain: app.domain, ip_address: app.gatekeeper_node.ip_address)
        payload = {domain: app.domain, name: app.name, application_key: app.public_key, owner_email: app.owner.email_address,
          branding: (app.owner.account_branding_profile || app.requested_by.account_branding_profile)&.attributes&.slice("brand_name", "logo_url", "support_email", "accent_color"),
          certificate_email: app.owner.email_address, deployment: runtime.deployment_config,
          owner: {first_name: app.owner.respond_to?(:first_name) ? app.owner.first_name : "Site",
            last_name: app.owner.respond_to?(:last_name) ? app.owner.last_name : "Owner"}}
        receipt = Fleet::Transport.run!(node: app.gatekeeper_node, domain: runtime.domain,
          requested_by: app.requested_by.email_address, operation_id: operation.id,
          payload: payload, script_name: "create_hosted_site.py")
        raise Access::Denied, "Application routing verification failed" unless receipt["status"] == "succeeded" &&
          receipt["domain"] == app.domain && receipt["application_key"] == app.public_key && receipt["site_id"].to_i.positive?
        app.update!(status: "ready", remote_site_id: receipt["site_id"], receipt: receipt)
        operation.update!(status: "succeeded", result: receipt, exit_status: 0, completed_at: Time.current)
      rescue StandardError => error
        safe = error.is_a?(Access::Denied) ? error.message : "Application setup failed (#{error.class}); retry uses the same site reservation."
        app.update!(status: "failed", error_message: safe) unless app.status == "deleted" || app.status == "ready"
        operation&.update!(status: "failed", error_class: error.class.name, error_message: safe, completed_at: Time.current)
      end

      def self.retry!(actor:, app:)
        LightekIdentity::Permissions.application!(actor,app,"manage")
        raise Access::Denied, "Only failed applications can be retried" unless app.status == "failed"
        app.update!(requested_by: actor)
        ProvisionApplicationJob.perform_later(app.id)
      end
    end
  end
end
