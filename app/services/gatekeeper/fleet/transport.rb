require "json"
require "timeout"
require "shellwords"

module Gatekeeper
  module Fleet
    class Transport
      class RemoteFailure < StandardError
        attr_reader :receipt
        def initialize(receipt)
          @receipt = receipt.slice("domain", "source_sha", "image", "target_id", "attempt", "previous_version",
            "database_backup", "status", "migration_started", "code_restored", "error_class", "adapter", "component", "repository", "log_path")
          super("Remote update failed")
        end
      end
      # Reuse the installer's audited SSH access, including policies on existing
      # node credentials. No website-owner credential is required or changed.
      def self.call!(target)
        installation = target.gatekeeper_installation
        node = installation.gatekeeper_node
        release = target.gatekeeper_rollout.gatekeeper_release
        raise Rollouts::Invalid, "Managed updates require a remote root SSH target" if node.local? || node.ssh_user != "root"
        credentials = []
        checkout = lambda do |slug, purpose, consumer = WebsiteDeployment::CONSUMER|
          payload = LightekVault::Service.checkout!(slug: slug, consumer: consumer, purpose: purpose,
            requested_by: target.gatekeeper_rollout.requested_by, gatekeeper_operation_id: target.gatekeeper_operation_id)
          credentials << payload
          payload
        end
        options = {port: node.ssh_port, non_interactive: true, verify_host_key: :accept_new,
          timeout: 20, keepalive: true, keepalive_interval: 20}
        if node.ssh_key_path.present?
          options[:keys] = [node.ssh_key_path]
        else
          config = node.metadata.to_h.fetch("website_deployments", {}).fetch(installation.domain, {})
          secret = checkout.call(config["credential_slug"], "website_deploy") if config["credential_slug"].present?
          options[:key_data] = [secret["ssh_private_key"]] if secret && secret["ssh_private_key"].present?
          options[:password] = secret["ssh_password"] if secret && secret["ssh_password"].present?
          if !options[:key_data] && !options[:password] && node.metadata.to_h["node_credential_secret_slug"].present?
            root = checkout.call(node.metadata.fetch("node_credential_secret_slug"), "node_bootstrap")
            options[:password] = root.fetch("root_password")
          end
        end
        payload = {domain: installation.domain, source_sha: release.source_sha, image: release.image,
          backward_compatible: release.backward_compatible?, target_id: target.id, attempt: target.attempts,
          expected_previous_sha: installation.current_version}.merge(Adapters.payload(installation, release))
        if installation.adapter == "docker_compose" && ENV["LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"].present?
          registry = checkout.call(ENV.fetch("LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"), "fleet_registry", name)
          payload[:registry] = registry.slice("username", "password")
        end
        require "net/ssh"
        # Full bounded execution; remote 'timeout' also survives a worker disconnect.
        Timeout.timeout(1900) do
          Net::SSH.start(node.ip_address, node.ssh_user, **options) do |ssh|
            script = Rails.root.join("lib/scripts/gatekeeper", Adapters.script(installation.adapter)).read
            command = "timeout --signal=TERM --kill-after=30s 1800s python3 -c #{Shellwords.escape(script)}"
            stdout = +""
            exit_status = nil
            ssh.open_channel do |ch|
              ch.exec(command) do |_, success|
                raise Rollouts::Invalid, "Remote updater did not start" unless success
                ch.send_data(JSON.generate(payload)); ch.eof!
                ch.on_data { |_, data| stdout << data if stdout.bytesize < 32_768 }
                ch.on_extended_data { |_, _, _data| } # Never persist docker/subprocess credential-bearing output.
                ch.on_request("exit-status") { |_, data| exit_status = data.read_long }
              end
            end
            ssh.loop
            receipt = JSON.parse(stdout)
            raise RemoteFailure.new(receipt) unless exit_status == 0
            receipt
          end
        end
      ensure
        credentials&.each { |secret| secret.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? } }
        payload&.clear
      end
    end
  end
end
