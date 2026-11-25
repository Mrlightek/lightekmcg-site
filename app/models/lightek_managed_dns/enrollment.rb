require "digest"
require "json"
require "ipaddr"
require "public_suffix"
require "resolv"
require "securerandom"

module LightekManagedDns
  class Enrollment < ApplicationRecord
    self.table_name = "lightek_managed_dns_enrollments"
    class Invalid < StandardError; end
    ROLLOUT_FLAG = "managed_dns"
    ROLLOUT_PAUSED = "New Managed DNS enrollments and cutovers are paused for this account."

    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :owner, class_name: "User"
    belongs_to :requested_by, class_name: "User"
    belongs_to :reviewed_by, class_name: "User", optional: true

    def powerdns? = provider_kind == "powerdns"

    def self.configured_provider
      provider = ENV.fetch("LIGHTEK_MANAGED_DNS_PROVIDER", "powerdns")
      raise Invalid, "Managed DNS provider is unavailable." unless provider.in?(%w[cloudflare powerdns])
      provider
    end

    def self.configured_nameservers
      ENV.fetch("LIGHTEK_MANAGED_DNS_NAMESERVERS", "ns1.lightekmcg.com,ns2.lightekmcg.com").split(",").map(&:strip)
    end

    def provider_for(actor)
      (powerdns? ? PowerDns : Cloudflare).new(actor)
    end

    def self.owner_for(order)
      order.hosting_owner || User.find_by(email_address: order.customer_email)
    end

    def self.rollout_enabled?(order, owner: owner_for(order))
      LightekFeatureFlags::Flag.enabled?(ROLLOUT_FLAG, account: owner, installation: -> { fleet_installation(order) })
    end

    def self.with_rollout!(order, owner:, &operation)
      LightekFeatureFlags::Flag.with_enabled!(ROLLOUT_FLAG, account: owner, installation: -> { fleet_installation(order) }, &operation)
    rescue LightekFeatureFlags::Flag::Unavailable
      raise Invalid, ROLLOUT_PAUSED
    end

    def self.fleet_installation(order)
      node_id = ProvisioningRequest.find_by(id: order.provisioning_request_id)&.gatekeeper_node_id
      return unless node_id

      GatekeeperInstallation.find_by(gatekeeper_node_id: node_id, domain: LightekCommerce::Installations.hostname(order), component: "lightek_app")
    end
    private_class_method :fleet_installation

    def self.domain_for(order)
      return unless LightekCommerce::Installations.ready?(order) && LightekCommerce::Installations.external_dns?(order)

      domain = PublicSuffix.domain(LightekCommerce::Installations.hostname(order), ignore_private: true, default_rule: nil)
      platform = PublicSuffix.domain(ENV.fetch("LIGHTEK_AUTO_CLIENT_BASE_DOMAIN", "lightekmcg.com"))
      infrastructure = configured_nameservers.filter_map { |host| PublicSuffix.domain(host) }
      domain unless domain.in?([platform, "lightekmcg.com", *infrastructure])
    end

    def self.request!(order:, actor:)
      owner = owner_for(order)
      domain = domain_for(order)
      raise Invalid, "Use a ready installation with a customer domain you manage." unless owner && domain &&
        Gatekeeper::Hosting::Access.manages?(actor, owner)

      order.with_lock do
        existing = find_by(order: order)
        return existing if existing && existing.state != "withdrawn"

        enrollment = existing || new(order: order)
        with_rollout!(order, owner: owner) do
          enrollment.update!(owner: owner, domain: domain, requested_by: actor, proof: SecureRandom.hex(24),
            provider_kind: configured_provider,
            state: "requested", provider_zone_id: nil, records_digest: nil, previous_nameservers: [], nameservers: [],
            reviewed_by: nil, reviewed_at: nil, verified_at: nil)
        end
        enrollment
      end
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, "This domain already has a managed DNS request."
    end

    def proof_name = "_lightek-dns.#{domain}"

    def stage!(actor:, provider:, zone_id:)
      require_operator!(actor)
      with_lock do
        raise Invalid, "Only pending requests can be staged." unless state.in?(%w[requested staged])
        require_rollout!
        verify_ownership!
        current = public_nameservers
        zone = provider.zone!(zone_id, domain)
        proposed = reviewed_nameservers!(provider, zone)
        raise Invalid, "Keep the current nameservers in place during review." if current.empty? || (current & proposed).any?

        records = provider_records(provider, zone_id, zone)
        verify_website!(records)
        verify_authority!(provider, zone, proposed)
        self.class.with_rollout!(order, owner: owner) do
          update!(state: "staged", provider_zone_id: zone_id, previous_nameservers: current, nameservers: proposed,
            records_digest: digest(records))
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, "That provider zone is already bound to another request."
    end

    def approve!(actor:, provider:)
      require_operator!(actor)
      with_lock do
        raise Invalid, "Stage the zone before approving it." unless state == "staged"
        require_rollout!
        verify_ownership!
        raise Invalid, "The current nameservers changed. Stage the zone again." unless public_nameservers == previous_nameservers
        verify_staged!(provider)
        self.class.with_rollout!(order, owner: owner) do
          update!(state: "awaiting_delegation", reviewed_by: actor, reviewed_at: Time.current)
        end
      end
    end

    def verify!(provider:)
      with_lock do
        raise Invalid, "This domain is not awaiting a nameserver check." unless state.in?(%w[awaiting_delegation active])
        zone = provider.zone!(provider_zone_id, domain)
        unless (powerdns? || zone["status"] == "active") && brand_nameservers!(provider, zone) == nameservers && public_nameservers == nameservers
          raise Invalid, "The nameserver change has not been verified yet."
        end
        verify_records!(provider, zone) if state == "awaiting_delegation"
        verify_authority!(provider, zone, nameservers)
        hostname = LightekCommerce::Installations.hostname(order)
        addresses = resolve(hostname, Resolv::DNS::Resource::IN::A) + resolve(hostname, Resolv::DNS::Resource::IN::AAAA)
        raise Invalid, "The website does not resolve to its registered VPS." unless addresses.map { |row| row.address.to_s }.uniq == [server_ip]

        update!(state: "active", verified_at: Time.current)
      end
    end

    def withdraw!
      with_lock do
        unless state.in?(%w[requested staged]) ||
            (state.in?(%w[awaiting_delegation active]) && previous_nameservers.present? && public_nameservers == previous_nameservers)
          raise Invalid, "Restore the previous nameservers before closing this enrollment."
        end
        update!(state: "withdrawn")
      end
    end

    def records(provider)
      return [] unless provider_zone_id && state != "withdrawn"

      zone = provider.zone!(provider_zone_id, domain)
      provider_records(provider, provider_zone_id, zone)
    end

    def record_revision(records)
      digest(records)
    end

    def editable_rrset?(name, type)
      website = LightekCommerce::Installations.hostname(order)
      PowerDns::EDITABLE_TYPES.include?(type) && name != proof_name && !(name == website && type.in?(%w[A AAAA CNAME]))
    end

    def change_rrset!(actor:, provider:, attributes:, remove: false)
      with_lock do
        unless powerdns? && state == "active" && self.class.owner_for(order.reload) == owner &&
            self.class.domain_for(order) == domain && Gatekeeper::Hosting::Access.manages?(actor, owner)
          raise Invalid, "Active Lightek DNS and access to this domain are required."
        end
        raise Invalid, "Verify that this domain still uses Lightek nameservers before editing." unless public_nameservers == nameservers

        name = attributes.fetch(:record_name, "").strip.downcase.delete_suffix(".")
        name = domain if name == "@"
        labels = name.split(".", -1)
        valid = name.bytesize <= 253 && labels.all? { |label| label.match?(/\A(?:\*|[a-z0-9_-]{1,63})\z/) } &&
          labels.drop(1).exclude?("*") && (name == domain || name.end_with?(".#{domain}"))
        raise Invalid, "Use @ or a hostname within #{domain}." unless valid

        type = attributes.fetch(:record_type, "")
        raise Invalid, "Choose a supported record type." unless PowerDns::EDITABLE_TYPES.include?(type)
        unless editable_rrset?(name, type)
          raise Invalid, "This record is reserved for the hosted application or its ownership proof."
        end

        current = records(provider)
        raise Invalid, "The zone changed. Reload the DNS records before editing." unless digest(current) == attributes[:revision]
        existing = current.select { |row| row["name"] == name && row["type"] == type }
        raise Invalid, "This record set no longer exists." if remove && existing.empty?

        unless remove
          ttl, contents = record_values!(attributes)
        end
        audit = {enrollment_id: id, actor_id: actor.id, record_name: name, record_type: type, operation: remove ? "delete" : "replace"}
        Rails.logger.info("[Lightek DNS] #{audit.merge(status: 'requested').to_json}")
        replication = provider.write_rrset!(domain: domain, name: name, type: type, ttl: ttl, contents: contents, remove: remove)
        Rails.logger.info("[Lightek DNS] #{audit.merge(status: 'accepted_by_primary', replication: replication).to_json}")
        replication
      end
    end

    private

    def require_rollout!
      raise Invalid, ROLLOUT_PAUSED unless self.class.rollout_enabled?(order, owner: owner)
    end

    def require_operator!(actor)
      raise Invalid, "A Lightek operator must review the DNS zone." unless Gatekeeper::Hosting::Access.super_admin?(actor)
    end

    def verify_ownership!
      answers = resolve(proof_name, Resolv::DNS::Resource::IN::TXT)
      raise Invalid, "Publish the ownership TXT record at the current DNS provider first." unless answers.any? { |row| row.strings.join == proof }
    end

    def reviewed_nameservers!(provider, zone)
      raise Invalid, "The provider zone must be pending during migration review." unless powerdns? || zone["status"] == "pending"
      brand_nameservers!(provider, zone)
    end

    def verify_authority!(provider, zone, servers)
      return unless powerdns?

      provider.verify_authority!(zone, nameservers: servers, website: LightekCommerce::Installations.hostname(order), ip: server_ip)
    end

    def brand_nameservers!(provider, zone)
      desired = normalize_nameservers(self.class.configured_nameservers)
      assigned = normalize_nameservers(provider.nameservers!(zone))
      unless desired.size.between?(2, 5) && assigned == desired &&
          desired.all? { |host| LightekSettings::SiteDomain.public_hostname?(host) }
        raise Invalid, "The zone does not have the configured Lightek nameservers."
      end
      desired
    end

    def verify_staged!(provider)
      zone = provider.zone!(provider_zone_id, domain)
      raise Invalid, "Stage the pending nameserver assignment again." unless reviewed_nameservers!(provider, zone) == nameservers
      verify_records!(provider, zone)
      verify_authority!(provider, zone, nameservers)
    end

    def verify_records!(provider, zone)
      raise Invalid, "DNS records changed after staging. Contact Lightek for another review." unless digest(provider_records(provider, provider_zone_id, zone)) == records_digest
    end

    def provider_records(provider, id, zone)
      powerdns? ? provider.records!(id, zone: zone) : provider.records!(id)
    end

    def verify_website!(records)
      host = LightekCommerce::Installations.hostname(order)
      web = records.select { |row| row["name"] == host && row["type"].in?(%w[A AAAA CNAME]) && !row["disabled"] }
      unless web.one? && web.first.values_at("type", "content", "proxied") == ["A", server_ip, false]
        raise Invalid, "Stage a single DNS-only A record pointing the website to its allocated VPS."
      end
    end

    def record_values!(attributes)
      ttl = Integer(attributes.fetch(:ttl, ""), 10, exception: false)
      text = attributes.fetch(:record_values, "")
      raise Invalid, "Use a TTL from 60 to 86,400 seconds." unless ttl&.between?(60, 86_400)
      raise Invalid, "Enter up to 25 single-line DNS values." if text.bytesize > 12_000 || text.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)

      values = text.lines.map(&:strip).reject(&:blank?).uniq
      raise Invalid, "Enter up to 25 single-line DNS values." unless values.size.between?(1, 25) && values.all? { |value| value.bytesize <= 1_000 }
      [ttl, values]
    end

    def server_ip
      request = ProvisioningRequest.find_by(id: order.provisioning_request_id)
      node = request&.gatekeeper_node
      unless request&.owner == owner && node&.ip_address.present?
        raise Invalid, "The installation has no registered VPS address."
      end
      Gatekeeper::Hosting::Access.active!(node)
      IPAddr.new(node.ip_address).to_s
    rescue Gatekeeper::Hosting::Access::Denied, IPAddr::InvalidAddressError
      raise Invalid, "The installation's VPS is unavailable."
    end

    def public_nameservers
      normalize_nameservers(resolve(domain, Resolv::DNS::Resource::IN::NS).map(&:name))
    end

    def normalize_nameservers(values)
      Array(values).map { |name| name.to_s.strip.downcase.delete_suffix(".") }.reject(&:empty?).uniq.sort
    end

    def resolve(name, type)
      Resolv::DNS.open { |dns| dns.timeouts = [2, 3]; dns.getresources("#{name}.", type) }
    end

    def digest(records)
      Digest::SHA256.hexdigest(records.map { |row| JSON.generate(row.sort.to_h) }.sort.join("\n"))
    end
  end
end
