# frozen_string_literal: true

require "resolv"
require "ipaddr"

module Gatekeeper
  # Publish the allocated public IPv4 before running the website packager.
  # DNS providers must be explicitly configured; never claim a record was
  # published when only an internal dashboard row exists.
  class WebsiteDnsPublication
    class NotConfigured < StandardError; end
    class Conflict < StandardError; end
    class NotPropagated < StandardError; end

    def self.call!(hostname:, ipv4:)
      host = hostname.to_s.downcase.strip
      address = IPAddr.new(ipv4.to_s)
      raise ArgumentError, "Expected public IPv4" unless address.ipv4? && !address.private? && !address.loopback? && !address.link_local?

      zones = Godaddy::DnsService.zones.sort_by { |zone| -zone.length }
      zone = zones.find { |candidate| host.end_with?(".#{candidate}") }
      raise NotConfigured, "No managed authoritative DNS zone for #{host}" unless zone

      name = host.delete_suffix(".#{zone}")
      raise ArgumentError, "Invalid DNS record name" unless name.match?(/\A[a-z0-9-]+(?:\.[a-z0-9-]+)*\z/)

      dns = Godaddy::DnsService.new(zone: zone)
      existing = dns.records.select do |record|
        record["name"].to_s.downcase == name && record["type"].to_s.upcase == "A"
      end
      if existing.empty?
        dns.create_record!("name" => name, "type" => "A", "data" => ipv4.to_s, "ttl" => 600)
      elsif existing.one? && existing.first["data"].to_s == ipv4.to_s
        # The only existing A record already points to this instance.
      elsif existing.one? && (existing.first["recordId"].presence || existing.first["id"].presence).present?
        dns.update_record!(existing.first["recordId"].presence || existing.first.fetch("id"), "name" => name, "type" => "A", "data" => ipv4.to_s, "ttl" => 600)
      else
        # A matching record among several conflicting A records is NOT success.
        # Leaving old instance IPs published would route customers incorrectly.
        raise Conflict, "Multiple or unidentifiable A records exist for #{host}"
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
      loop do
        addresses = Resolv.getaddresses(host)
        return { "hostname" => host, "ipv4" => ipv4.to_s, "provider" => "godaddy", "verified" => true } if addresses.include?(ipv4.to_s)
        raise NotPropagated, "DNS for #{host} does not resolve to allocated node #{ipv4}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 5
      end
    end
  end
end
