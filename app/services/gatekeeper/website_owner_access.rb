# frozen_string_literal: true
require "json"
require "shellwords"
require "uri"
require "digest"
require "timeout"

module Gatekeeper
  # Runs on the control plane. Only the verified buyer or a platform super admin
  # may obtain a native, expiring password-reset link for this isolated instance.
  module WebsiteOwnerAccess
    RESET_RUNNER = <<~'CODE'.freeze
      require "json"
      input = JSON.parse(STDIN.read)
      user = User.find_by!(email_address: input.fetch("owner_email"))
      raise "Owner is not an administrator" unless %w[admin super_admin].include?(user.role)
      puts "LIGHTEK_OWNER_ACCESS=" + JSON.generate(token: user.generate_token_for(:password_reset))
    CODE

    def owner_password_setup_url!(actor:, order:)
      policy = LightekCommerce::Installations
      raise WebsiteDeployment::Invalid, "Installation access denied" unless policy.can_manage_access?(actor, order) && policy.ready?(order)
      request = ProvisioningRequest.find(order.provisioning_request_id)
      node = request.gatekeeper_node
      raise WebsiteDeployment::Invalid, "Installation ownership mismatch" unless node && request.owner == node.owner && request.owner.email_address == order.customer_email
      domain = policy.hostname(order)
      config = preview_for_owner_access(node: node, domain: domain, owner: request.owner)
      Gatekeeper::Compute::NodeVerificationService.call(request: request, requested_by: actor.email_address)
      operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: "website_owner_access", requested_by: actor.email_address,
        parameters: {order_id: order.id, owner_id: request.owner.id}, status: "running", started_at: Time.current)
      secret = LightekVault::Service.checkout!(slug: node.metadata.fetch("node_credential_secret_slug"),
        consumer: WebsiteDeployment::CONSUMER, purpose: "node_bootstrap", requested_by: actor.email_address, gatekeeper_operation_id: operation.id)
      require "net/ssh"
      root = "/opt/lightek-sites/#{domain}"
      project = "lt_#{Digest::SHA256.hexdigest(domain)[0, 16]}"
      command = Shellwords.join(["docker", "compose", "--env-file", "#{root}/.env", "-p", project,
        "-f", "#{root}/compose.yml", "exec", "-T", "web", "bin/rails", "runner", RESET_RUNNER])
      output = String.new
      exit_status = nil
      Net::SSH.start(node.ip_address, node.ssh_user, port: node.ssh_port, password: secret.fetch("root_password"),
        non_interactive: true, verify_host_key: :accept_new, timeout: 20) do |ssh|
        ssh.open_channel do |channel|
          channel.exec(command) do |ch, success|
            raise WebsiteDeployment::Invalid, "Owner access command was rejected" unless success
            ch.send_data(JSON.generate(owner_email: config.fetch("owner_email", request.owner.email_address)))
            ch.eof!
          end
          channel.on_data { |_ch, data| raise WebsiteDeployment::Invalid, "Unexpected access response" if output.bytesize + data.bytesize > 65_536; output << data }
          channel.on_extended_data { |_ch, _type, _data| }
          channel.on_request("exit-status") { |_ch, data| exit_status = data.read_long }
        end
        Timeout.timeout(60) { ssh.loop }
      end
      marker = output.lines.find { |line| line.start_with?("LIGHTEK_OWNER_ACCESS=") }
      raise WebsiteDeployment::Invalid, "Password setup could not be issued" unless exit_status == 0 && marker
      token = JSON.parse(marker.delete_prefix("LIGHTEK_OWNER_ACCESS=")).fetch("token")
      raise WebsiteDeployment::Invalid, "Invalid password setup response" unless token.is_a?(String) && token.bytesize.between?(32, 4096) && !token.match?(/[\r\n]/)
      operation.update!(status: "succeeded", completed_at: Time.current, exit_status: 0, result: {link_issued: true})
      "https://#{domain}/passwords/#{URI.encode_www_form_component(token)}/edit"
    rescue StandardError => error
      operation&.update!(status: "failed", completed_at: Time.current, error_class: error.class.name, error_message: "Owner access link could not be issued")
      raise WebsiteDeployment::Invalid, "Owner access link could not be issued"
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      output&.clear
    end

    def preview_for_owner_access(node:, domain:, owner:)
      receipt = node.metadata.to_h.fetch("website_deployment", {})
      config = node.metadata.to_h.fetch("website_deployments", {}).fetch(domain)
      raise WebsiteDeployment::Invalid, "Installation receipt mismatch" unless config.fetch("owner_id") == owner.id &&
        receipt["url"] == "https://#{domain}" && receipt["public_https_verified"] == true && receipt["owner_login_verified"] == true &&
        receipt.dig("health", "full_application_dashboard_verified") == true
      config
    end
  end
end
