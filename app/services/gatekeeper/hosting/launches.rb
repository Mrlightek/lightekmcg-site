module Gatekeeper
  module Hosting
    class Launches
      def self.create!(actor:, attributes:)
        # Installing arbitrary software and allocating provider resources require an operator.
        raise Access::Denied, "A super admin installs application templates; additional websites use your plan allowance." unless Access.super_admin?(actor)
        template = GatekeeperApplicationTemplate.available.find(attributes.fetch("template_id"))
        owner = User.find(attributes["owner_id"].presence || actor.id)
        domain = LightekSettings::SiteDomain.public_hostname!(attributes.to_h.with_indifferent_access.fetch("domain"))
        #domain = LightekSettings::SiteDomain.public_hostname!(attributes.fetch("domain"))
        node = Access.nodes(actor).find(attributes["node_id"]) if attributes["node_id"].present?
        Access.active!(node) if node
        launch = nil
        owner.with_lock do
          raise Access::Denied, "Hostname is already assigned" if Access.site_domains(owner).include?(domain) ||
            GatekeeperProject.exists?(domain: domain) || GatekeeperHostedApplication.exists?(domain: domain)
          GatekeeperApplicationLaunch.transaction do
            request = nil
            unless node
              provider = ComputeProvider.active.find(attributes.fetch("compute_provider_id"))
              raise Access::Denied, "New server allocation currently supports Linode" unless provider.slug == "linode" && provider.health_status == "healthy"
              catalog = Compute::LinodeCatalogService.call(provider: provider, requested_by: actor.email_address, region: attributes.fetch("region"))
              plan = catalog.fetch("plans").find { |p| p["id"] == attributes["plan"] } || raise(Access::Denied, "Select a provider plan")
              raise Access::Denied, "Select a provider region" unless catalog.fetch("regions").any? { |r| r["id"] == attributes["region"] }
              raise Access::Denied, "Use Ubuntu 24.04 for automated application installation" unless catalog.fetch("images").any? { |i| i["id"] == "linode/ubuntu24.04" }
              raise Access::Denied, "Provider did not return a monthly price" unless plan["monthly_cents"].to_i.positive?
              label = attributes["server_name"].presence || "#{attributes.fetch('name').parameterize.first(40)}-#{SecureRandom.hex(4)}"
              raise Access::Denied, "Server name must be 3–64 letters, numbers, hyphens or underscores" unless label.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}\z/)
              request = ProvisioningRequest.create!(owner: owner, compute_provider: provider, requested_node_count: 1,
                selected_region: attributes["region"], selected_plan: plan.fetch("id"), selected_image: "linode/ubuntu24.04",
                node_label: label, estimated_monthly_cost_cents: plan.fetch("monthly_cents"),
                approval_status: "approved", execution_status: "ready", approved_by: actor.email_address,
                approved_at: Time.current, approval_reason: "Server creation requested by super admin in Dashboard")
            end
            Access.active!(node) if node
            launch = GatekeeperApplicationLaunch.create!(gatekeeper_application_template: template, owner: owner,
              requested_by: actor, name: attributes.fetch("name"), domain: domain, gatekeeper_node: node,
              provisioning_request: request, template_snapshot: template.attributes.slice("kind", "image", "container_port", "credential_slug", "rails_database", "rails_worker"))
          end
        end
        LaunchApplicationJob.perform_later(launch.id)
        launch
      rescue LightekSettings::SiteDomain::Invalid => error
        raise Access::Denied, error.message
      end

      def self.wait_for_ssh!(node)
        require "socket"
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 600
        loop do
          begin
            Socket.tcp(node.ip_address, node.ssh_port, connect_timeout: 5) { |socket| socket.close }
            return
          rescue SystemCallError, IOError, SocketError
            raise Access::Denied, "Server SSH is not ready. Retry will use this server." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 5
          end
        end
      end

      def self.perform!(launch)
        launch.with_lock do
          return if %w[ready deleted provisioning].include?(launch.status)
          raise Access::Denied, "The requesting account is no longer an operator" unless Access.super_admin?(launch.requested_by)
          if launch.gatekeeper_node
            launch.gatekeeper_node.with_lock do
              Access.authorize!(launch.requested_by, launch.gatekeeper_node)
              Access.active!(launch.gatekeeper_node)
              launch.update!(status: "provisioning", error_message: nil)
            end
          else
            launch.update!(status: "provisioning", error_message: nil)
          end
        end
        actor, domain = launch.requested_by, launch.domain
        config = launch.template_snapshot
        request = launch.provisioning_request
        if request && !request.gatekeeper_node_id && request.approved? && request.execution_status == "failed"
          request.update!(execution_status: "ready")
        end
        if config.fetch("kind") == "native_rails"
          slug = "application-launch-#{launch.id}"
          unless (launch.gatekeeper_node || request).metadata.to_h.fetch("website_deployments", {}).key?(domain)
            LightekVault::Service.store!(name: "Application #{launch.id}", slug: slug,
              payload: {"owner_password" => SecureRandom.urlsafe_base64(36)}, provider: "lightek", purpose: "website_deploy",
              access_policy: {"consumers" => [WebsiteDeployment::CONSUMER], "purposes" => ["website_deploy"]}, requested_by: actor.email_address)
            site = WebsiteDeployment.configuration(owner: launch.owner, domain: domain, site_name: launch.name,
              headline: "Welcome", description: launch.name, certificate_email: launch.owner.email_address, credential_slug: slug)
            WebsiteDeployment.register!(actor: actor, record: launch.gatekeeper_node || request, config: site)
          end
          receipt = request ? WebsiteDeployment.provision_and_run!(actor: actor, request: request, domain: domain) :
            WebsiteDeployment.run!(actor: actor, node: launch.gatekeeper_node, domain: domain)
          raise Access::Denied, "Rails application verification failed" unless receipt[:verified] == true
          launch.update!(gatekeeper_node: launch.gatekeeper_node || request.reload.gatekeeper_node, receipt: receipt, status: "ready")
        else
          node = launch.gatekeeper_node || request.reload.gatekeeper_node ||
            Compute::ProvisioningExecutionService.call(request: request, requested_by: actor.email_address)
          launch.update!(gatekeeper_node: node)
          Access.authorize!(actor, node)
          raise Access::Denied, "Server is pending deletion" if %w[deleting delete_failed decommissioned].include?(node.status)
          wait_for_ssh!(node) if request
          Dns.prepare!(domain: domain, ip_address: node.ip_address)
          secrets = {}
          if config["credential_slug"].present?
            secrets = LightekVault::Service.checkout!(slug: config["credential_slug"], consumer: name,
              purpose: "application_install", requested_by: actor.email_address)
          end
          operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: "install_container_application",
            requested_by: actor.email_address, status: "running", started_at: Time.current, parameters: {launch_id: launch.id, domain: domain})
          receipt = Fleet::Transport.run!(node: node, domain: domain, requested_by: actor.email_address,
            operation_id: operation.id, script_name: "install_container_application.py", registry: true,
            payload: {domain: domain, launch_id: launch.id, image: config.fetch("image"),
              container_port: config.fetch("container_port"), rails_database: config.fetch("rails_database"), rails_worker: config.fetch("rails_worker", false),
              email: launch.owner.email_address, environment: secrets.fetch("environment", {})})
          raise Access::Denied, "Container HTTPS verification failed" unless receipt["status"] == "succeeded" && receipt["domain"] == domain && receipt["image"] == config["image"]
          operation.update!(status: "succeeded", completed_at: Time.current, result: receipt, exit_status: 0)
          launch.update!(status: "ready", receipt: receipt)
          node.update!(status: "healthy")
        end
        begin
          MailPortRequest.submit!(request: request.reload, actor: actor, domain: domain) if request
        rescue StandardError => error
          launch.update!(receipt: launch.receipt.merge("mail_port_status" => "pending", "mail_port_error" => error.class.name))
          begin
            MailPortRequestJob.perform_later(launch.id)
          rescue StandardError
            Rails.logger.warn("[Hosting] mail request retry will be recovered for launch #{launch.id}")
          end
        end
      rescue StandardError => error
        operation&.update!(status: "failed", error_class: error.class.name, error_message: "Application installation failed", completed_at: Time.current)
        launch.update!(gatekeeper_node: launch.gatekeeper_node || launch.provisioning_request&.reload&.gatekeeper_node,
          status: "failed", error_message: error.is_a?(Access::Denied) ? error.message : "Installation failed (#{error.class}). Retry reuses the same server and domain.")
        raise
      ensure
        secrets&.each_value { |value| value.clear if value.respond_to?(:clear) && !value.frozen? }
      end
    end
  end
end
