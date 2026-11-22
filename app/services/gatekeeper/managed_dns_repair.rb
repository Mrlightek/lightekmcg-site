# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Gatekeeper
  module ManagedDnsRepair
    class Conflict < StandardError; end

    module_function

    def project!(project)
      node = project.gatekeeper_node
      Hosting::Access.active!(node)
      address = IPAddr.new(node.ip_address)
      unless address.ipv4? && !address.private? && !address.loopback? && !address.link_local? && !address.to_i.zero?
        raise ArgumentError, "Project DNS requires a registered public IPv4 address"
      end

      reconcile!(hostname: project.domain, type: "A", value: address.to_s)
    end

    def mailbox!(account)
      raise ArgumentError, "Enable this mailbox and verify its domain first" unless account.enabled? && account.domain.verified_at?

      reconcile!(hostname: account.domain.name, type: "MX", value: LightekMail::ReceivingStatus.expected_host, priority: 10)
    end

    def reconcile!(hostname:, type:, value:, priority: nil)
      hostname = normalize_host(hostname)
      unless hostname.match?(/\A[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/) && value.match?(/\A[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/)
        raise ArgumentError, "Invalid managed DNS hostname or target"
      end

      zone = Godaddy::DnsService.zones.select { |entry| hostname == entry || hostname.end_with?(".#{entry}") }.max_by(&:length)
      raise Conflict, "No managed DNS zone covers this hostname" unless zone

      provider = Godaddy::DnsService.new(zone: zone)
      name = hostname == zone ? "@" : hostname.delete_suffix(".#{zone}")
      records = provider.records.select do |record|
        key = normalize_host(record["name"])
        [name, hostname].include?(key) && [type, "CNAME"].include?(record["type"].to_s.upcase)
      end
      observed = public_values(hostname, type)
      unless records.all? { |record| record["type"].to_s.upcase == type && normalize_host(record["data"]) == value } &&
          records.size <= 1 && (observed - [value]).empty?
        raise Conflict, "Existing DNS records conflict with the managed target"
      end

      created = records.empty? && observed.empty?
      if created
        provider.create_record!(name: name, type: type, data: value, ttl: 600, priority: priority)
      end
      verified = (created ? public_values(hostname, type) : observed) == [value]
      {"hostname" => hostname, "record_type" => type, "expected" => value, "created" => created,
        "status" => verified ? "verified" : "pending_dns", "verified" => verified}
    end
    private_class_method :reconcile!

    def public_values(hostname, type)
      record = type == "A" ? Resolv::DNS::Resource::IN::A : Resolv::DNS::Resource::IN::MX
      Resolv::DNS.open do |dns|
        dns.timeouts = 3
        aliases = dns.getresources("#{hostname}.", Resolv::DNS::Resource::IN::CNAME)
        raise Conflict, "This hostname already uses a public DNS alias" if aliases.any?

        dns.getresources("#{hostname}.", record).map do |entry|
          normalize_host(type == "A" ? entry.address : entry.exchange)
        end.uniq
      end
    end
    private_class_method :public_values

    def normalize_host(value) = value.to_s.strip.downcase.delete_suffix(".")
    private_class_method :normalize_host
  end
end
