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

    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :owner, class_name: "User"
    belongs_to :requested_by, class_name: "User"
    belongs_to :reviewed_by, class_name: "User", optional: true

    def self.owner_for(order)
      order.hosting_owner || User.find_by(email_address: order.customer_email)
    end

    def self.domain_for(order)
      return unless LightekCommerce::Installations.ready?(order) && LightekCommerce::Installations.external_dns?(order)

      domain = PublicSuffix.domain(LightekCommerce::Installations.hostname(order), ignore_private: true, default_rule: nil)
      platform = PublicSuffix.domain(ENV.fetch("LIGHTEK_AUTO_CLIENT_BASE_DOMAIN", "lightekmcg.com"))
      domain unless domain.in?([platform, "lightekmcg.com"])
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
        enrollment.update!(owner: owner, domain: domain, requested_by: actor, proof: SecureRandom.hex(24),
          state: "requested", provider_zone_id: nil, records_digest: nil, previous_nameservers: [], nameservers: [],
          reviewed_by: nil, reviewed_at: nil, verified_at: nil)
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
        verify_ownership!
        current = public_nameservers
        proposed = reviewed_zone!(provider, zone_id)
        raise Invalid, "Keep the current nameservers in place during review." if current.empty? || (current & proposed).any?

        records = provider.records!(zone_id)
        verify_website!(records)
        update!(state: "staged", provider_zone_id: zone_id, previous_nameservers: current, nameservers: proposed,
          records_digest: digest(records))
      end
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, "That provider zone is already bound to another request."
    end

    def approve!(actor:, provider:)
      require_operator!(actor)
      with_lock do
        raise Invalid, "Stage the zone before approving it." unless state == "staged"
        verify_ownership!
        raise Invalid, "The current nameservers changed. Stage the zone again." unless public_nameservers == previous_nameservers
        verify_staged!(provider)
        update!(state: "awaiting_delegation", reviewed_by: actor, reviewed_at: Time.current)
      end
    end

    def verify!(provider:)
      with_lock do
        raise Invalid, "This domain is not awaiting a nameserver check." unless state.in?(%w[awaiting_delegation active])
        zone = provider.zone!(provider_zone_id, domain)
        unless zone["status"] == "active" && brand_nameservers!(provider, zone) == nameservers && public_nameservers == nameservers
          raise Invalid, "The nameserver change has not been verified yet."
        end
        verify_records!(provider) if state == "awaiting_delegation"
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

      provider.zone!(provider_zone_id, domain)
      provider.records!(provider_zone_id)
    end

    private

    def require_operator!(actor)
      raise Invalid, "A Lightek operator must review the DNS zone." unless Gatekeeper::Hosting::Access.super_admin?(actor)
    end

    def verify_ownership!
      answers = resolve(proof_name, Resolv::DNS::Resource::IN::TXT)
      raise Invalid, "Publish the ownership TXT record at the current DNS provider first." unless answers.any? { |row| row.strings.join == proof }
    end

    def reviewed_zone!(provider, id)
      zone = provider.zone!(id, domain)
      raise Invalid, "The provider zone must be pending during migration review." unless zone["status"] == "pending"
      brand_nameservers!(provider, zone)
    end

    def brand_nameservers!(provider, zone)
      desired = normalize_nameservers(ENV.fetch("LIGHTEK_MANAGED_DNS_NAMESERVERS", "ns1.lightekmcg.com,ns2.lightekmcg.com").split(","))
      assigned = normalize_nameservers(provider.nameservers!(zone))
      unless desired.size.between?(2, 5) && assigned == desired &&
          desired.all? { |host| LightekSettings::SiteDomain.public_hostname?(host) }
        raise Invalid, "The zone does not have the configured Lightek nameservers."
      end
      desired
    end

    def verify_staged!(provider)
      raise Invalid, "Stage the pending nameserver assignment again." unless reviewed_zone!(provider, provider_zone_id) == nameservers
      verify_records!(provider)
    end

    def verify_records!(provider)
      raise Invalid, "DNS records changed after staging. Contact Lightek for another review." unless digest(provider.records!(provider_zone_id)) == records_digest
    end

    def verify_website!(records)
      host = LightekCommerce::Installations.hostname(order)
      web = records.select { |row| row["name"] == host && row["type"].in?(%w[A AAAA CNAME]) }
      unless web.one? && web.first.values_at("type", "content", "proxied") == ["A", server_ip, false]
        raise Invalid, "Stage a single DNS-only A record pointing the website to its allocated VPS."
      end
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
