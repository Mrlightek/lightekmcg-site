require "ipaddr"
module LightekConnect
  class Sandboxes
    CONSUMER = name.freeze
    def self.operator!(actor)
      raise Gatekeeper::Hosting::Access::Denied, "A super administrator manages disposable test environments" unless Gatekeeper::Hosting::Access.super_admin?(actor)
    end
    def self.create!(actor:, node_id:)
      operator!(actor)
      node = Gatekeeper::Hosting::Access.nodes(actor).find(node_id)
      Gatekeeper::Hosting::Access.active!(node)
      key = SecureRandom.hex(12)
      zone = LightekSettings::SiteDomain.public_hostname!(ENV.fetch("LIGHTEK_CONNECT_TEST_ZONE", "lightekmcg.com"))
      raise ArgumentError, "Choose a configured DNS zone for test environments" unless Godaddy::DnsService.zones.include?(zone)
      slug = "connect-wordpress-#{key}"
      LightekVault::Service.store!(name: "Disposable WordPress #{key}", slug: slug, provider: "wordpress", purpose: "connect_sandbox",
        payload: {"admin_username" => "lightek_test", "admin_password" => SecureRandom.hex(24), "database_password" => SecureRandom.hex(24)},
        access_policy: {"consumers" => [CONSUMER], "purposes" => ["connect_sandbox"]}, requested_by: actor.email_address)
      sandbox = Sandbox.create!(user: actor, gatekeeper_node: node, key: key, domain: "wp-test-#{key}.#{zone}", credential_slug: slug,
        metadata: {"zone" => zone, "ip_address" => node.ip_address})
      SandboxJob.perform_later(sandbox.id, "install")
      sandbox
    end
    def self.delete!(actor:, sandbox:, confirmation:)
      operator!(actor)
      raise ArgumentError, "Type the exact test hostname to delete its WordPress data" unless confirmation == sandbox.domain
      sandbox.with_lock do
        raise ArgumentError, "Wait for the current operation to finish" unless (%w[ready failed delete_failed].include?(sandbox.status) || (%w[queued installing destroying].include?(sandbox.status) && sandbox.updated_at < 40.minutes.ago))
        sandbox.update!(status: "deleting", error_message: nil)
      end
      SandboxJob.perform_later(sandbox.id, "delete")
    end
    def self.perform!(sandbox, action)
      raise ArgumentError unless %w[install delete].include?(action)
      operator!(sandbox.user)
      sandbox.with_lock do
        expected = action == "install" ? "queued" : "deleting"
        return unless sandbox.status == expected
        sandbox.update!(status: action == "install" ? "installing" : "destroying")
      end
      secret = nil
      begin
        Gatekeeper::Hosting::Access.active!(sandbox.gatekeeper_node)
        raise ArgumentError, "Test server address changed" unless sandbox.metadata.fetch("ip_address") == sandbox.gatekeeper_node.ip_address
        prepare_dns!(sandbox) if action == "install"
        secret = LightekVault::Service.checkout!(slug: sandbox.credential_slug, consumer: CONSUMER,
          purpose: "connect_sandbox", requested_by: sandbox.user.email_address) if action == "install"
        payload = {action: action, key: sandbox.key, domain: sandbox.domain, email: sandbox.user.email_address}
        if action == "install"
          payload[:credentials] = secret
          payload[:plugin_files] = Dir[Rails.root.join("integrations/wordpress/lightek-connect/**/*")].select { |p| File.file?(p) }.to_h do |path|
            [Pathname.new(path).relative_path_from(Rails.root.join("integrations/wordpress/lightek-connect")).to_s, File.read(path)]
          end
        end
        receipt = Gatekeeper::Fleet::Transport.run!(node: sandbox.gatekeeper_node, domain: sandbox.domain,
          requested_by: sandbox.user.email_address, operation_id: nil, script_name: "wordpress_sandbox.py", payload: payload)
        expected_status = action == "install" ? "ready" : "deleted"
        raise ArgumentError, "WordPress verification did not match the requested test environment" unless receipt["key"] == sandbox.key && receipt["domain"] == sandbox.domain && receipt["status"] == expected_status
        if action == "delete"
          remove_dns!(sandbox)
          LightekVault::Service.disable!(slug: sandbox.credential_slug, requested_by: sandbox.user.email_address)
        end
        sandbox.update!(status: expected_status, metadata: sandbox.metadata.merge("receipt" => receipt), error_message: nil)
      rescue StandardError => error
        reason = error.respond_to?(:receipt) ? error.receipt["reason"] : nil
        sandbox.update!(status: action == "delete" ? "delete_failed" : "failed", error_message: reason || "Test environment operation failed (#{error.class}). Review server prerequisites and retry cleanup.")
      ensure
        secret&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
      end
    end
    def self.credentials!(actor:, sandbox:)
      operator!(actor)
      raise ArgumentError, "WordPress is not ready" unless sandbox.status == "ready"
      secret = LightekVault::Service.checkout!(slug: sandbox.credential_slug, consumer: CONSUMER,
        purpose: "connect_sandbox", requested_by: actor.email_address)
      secret.slice("admin_username", "admin_password").transform_values(&:dup)
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end
    def self.prepare_dns!(sandbox)
      return if sandbox.metadata["dns_id"].present?
      zone = sandbox.metadata.fetch("zone")
      name = sandbox.domain.delete_suffix(".#{zone}")
      dns = Godaddy::DnsService.new(zone: zone)
      raise ArgumentError, "Test hostname is already in use" if dns.records.any? { |row| row["name"].to_s.delete_suffix(".#{zone}") == name }
      type = IPAddr.new(sandbox.metadata.fetch("ip_address")).ipv4? ? "A" : "AAAA"
      dns.create_record!(name: name, type: type, data: sandbox.metadata.fetch("ip_address"), ttl: 600)
      row = dns.records.find { |entry| entry["name"].to_s.delete_suffix(".#{zone}") == name && entry["type"] == type && entry["data"] == sandbox.metadata.fetch("ip_address") }
      raise ArgumentError, "DNS provider did not return an owned record identifier" unless row && row["id"].present?
      sandbox.update!(metadata: sandbox.metadata.merge("dns_id" => row["id"], "dns_type" => type))
    end
    def self.remove_dns!(sandbox)
      return unless sandbox.metadata["dns_id"].present?
      zone = sandbox.metadata.fetch("zone")
      dns = Godaddy::DnsService.new(zone: zone)
      row = dns.records.find { |entry| entry["id"].to_s == sandbox.metadata.fetch("dns_id").to_s }
      return unless row
      name = sandbox.domain.delete_suffix(".#{zone}")
      raise ArgumentError, "DNS record changed; cleanup stopped" unless row["name"].to_s.delete_suffix(".#{zone}") == name && row["type"] == sandbox.metadata.fetch("dns_type") && row["data"] == sandbox.metadata.fetch("ip_address")
      dns.delete_record!(row.fetch("id"))
    end
  end
end
