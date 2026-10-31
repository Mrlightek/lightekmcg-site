# frozen_string_literal: true

require "net/ssh"
require "shellwords"
require "digest"

module LightekCommerce
  # Repairs mail on the already-provisioned VPS; never allocates a node or
  # re-runs the customer website installer.
  class PendingMailRecoveryJob < ApplicationJob
    queue_as :default

    def perform(provisioning_request_id)
      request = ProvisioningRequest.find(provisioning_request_id)
      node = request.gatekeeper_node
      return unless node
      receipt = node.metadata.to_h["website_deployment"].to_h
      return unless receipt["mail_setup_status"] == "pending" || receipt["mail_registration_status"] == "pending"

      deployments = request.metadata.to_h.fetch("website_deployments", {})
      domain, config = deployments.find { |hostname, _| receipt["url"] == "https://#{hostname}" }
      raise "Missing customer deployment configuration for mail recovery" unless domain && config
      raise "Mail recovery requires a remote root node" if node.local? || node.ssh_user != "root"

      lock_root = Rails.root.join("tmp/lightek_deploy_locks")
      FileUtils.mkdir_p(lock_root, mode: 0o700)
      File.open(lock_root.join("node-#{node.id}.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        raise "Node deployment/recovery already running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        recover!(request:, node:, domain:, config:)
      end
    end

    private

    def recover!(request:, node:, domain:, config:)
      operator = User.find_by!(role: "super_admin")
      operation = GatekeeperOperation.create!(
        gatekeeper_node: node, capability: "recover_mail",
        requested_by: operator.email_address, parameters: {domain: domain},
        status: "running", started_at: Time.current
      )
      secrets = nil
      bootstrap = nil
      begin
        secrets = LightekVault::Service.checkout!(
          slug: config.fetch("credential_slug"), consumer: Gatekeeper::WebsiteDeployment::CONSUMER,
          purpose: "website_deploy", requested_by: operator.email_address,
          gatekeeper_operation_id: operation.id
        )
        unless secrets["ssh_password"].present? || secrets["ssh_private_key"].present? || node.ssh_key_path.present?
          bootstrap = LightekVault::Service.checkout!(
            slug: node.metadata.to_h.fetch("node_credential_secret_slug"),
            consumer: Gatekeeper::WebsiteDeployment::CONSUMER, purpose: "node_bootstrap",
            requested_by: operator.email_address, gatekeeper_operation_id: operation.id
          )
        end
        options = {port: node.ssh_port, non_interactive: true, verify_host_key: :accept_new, timeout: 20}
        password = secrets["ssh_password"] || bootstrap&.fetch("root_password")
        options[:password] = password if password.present?
        options[:key_data] = [secrets["ssh_private_key"]] if secrets["ssh_private_key"].present?
        options[:keys] = [node.ssh_key_path] if node.ssh_key_path.present?
        options[:auth_methods] = %w[publickey password keyboard-interactive]

        release = node.metadata.to_h.fetch("website_deployment").fetch("release")
        raise "Invalid deployment release" unless release.match?(/\A[a-zA-Z0-9._-]+\z/)
        raise "Invalid customer hostname" unless domain.match?(/\A[a-z0-9.-]+\z/)
        root = "/opt/lightek-sites/#{domain}"
        script = "#{root}/releases/#{release}/lib/scripts/setup_lightek_mail_node.sh"
        address = "admin@#{domain}"
        install = "LIGHTEK_MAIL_INITIAL_ADDRESS=#{Shellwords.escape(address)} LIGHTEK_MAIL_HOST=#{Shellwords.escape("mail.#{domain}")} LIGHTEK_MAIL_DKIM_DOMAIN=#{Shellwords.escape(domain)} bash #{Shellwords.escape(script)} --install"
        mailbox = "LIGHTEK_MAIL_INITIAL_ADDRESS=#{Shellwords.escape(address)} bash #{Shellwords.escape(script)} --mailbox-only"
        check = "systemctl is-active --quiet postfix && systemctl is-active --quiet dovecot && systemctl is-active --quiet rspamd && systemctl is-active --quiet lightek-mail-redis"
        compose_project = "lt_#{Digest::SHA256.hexdigest(domain)[0, 16]}"
        owner_email = config["owner_email"].presence || User.find(config.fetch("owner_id")).email_address
        register = [
          "docker", "compose", "--env-file", "#{root}/.env", "-p", compose_project,
          "-f", "#{root}/compose.yml", "run", "--rm", "-T",
          "-e", "LIGHTEK_INITIAL_MAIL_OWNER=#{owner_email}",
          "-e", "LIGHTEK_INITIAL_MAIL_ADDRESS=#{address}",
          "web", "bin/rails", "runner", "script/lightek_mail_account_bootstrap.rb"
        ].shelljoin

        Net::SSH.start(node.ip_address, node.ssh_user, **options) do |ssh|
          execute!(ssh, "test -f #{Shellwords.escape(script)}")
          execute!(ssh, "if #{check}; then #{mailbox}; else #{install}; fi")
          node.with_lock do
            current = node.metadata.to_h["website_deployment"].to_h
            node.update!(metadata: node.metadata.to_h.merge(
              "website_deployment" => current.merge("mail_setup_status" => "configured")
            ))
          end
          execute!(ssh, register)
        end
        node.with_lock do
          current = node.metadata.to_h["website_deployment"].to_h
          node.update!(metadata: node.metadata.to_h.merge(
            "website_deployment" => current.merge("mail_setup_status" => "configured",
              "mail_registration_status" => "registered")
          ))
        end
        operation.update!(status: "succeeded", exit_status: 0, completed_at: Time.current,
          result: {domain: domain, mail_setup_status: "configured", mail_registration_status: "registered"})
      rescue StandardError => error
        operation.update!(status: "failed", exit_status: 1, completed_at: Time.current,
          error_class: error.class.name, error_message: "Mail recovery failed; retry on existing node")
        raise
      ensure
        [secrets, bootstrap].compact.each do |payload|
          payload.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
        end
      end
    end

    def execute!(ssh, command)
      status = nil
      ssh.open_channel do |channel|
        channel.exec(command) do |ch, success|
          raise "Remote command rejected" unless success
          ch.on_request("exit-status") { |_c, data| status = data.read_long }
        end
      end
      ssh.loop
      raise "Remote mail operation failed (exit #{status || 'unknown'})" unless status == 0
    end
  end
end
