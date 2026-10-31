require "resolv"
require "ipaddr"
module Gatekeeper
  module Hosting
    class Dns
      def self.prepare!(domain:, ip_address:)
        target = IPAddr.new(ip_address)
        current = Resolv.getaddresses(domain)
        return if current.any? { |ip| IPAddr.new(ip) == target }
        zones = Godaddy::DnsService.zones.select { |zone| domain == zone || domain.end_with?(".#{zone}") }.sort_by { |zone| -zone.length }
        raise Access::Denied, "Point the hostname to this server and retry" if zones.empty?
        zone = zones.first
        name = domain == zone ? "@" : domain.delete_suffix(".#{zone}")
        service = Godaddy::DnsService.new(zone: zone)
        records = service.records.select { |row| row["name"].to_s.delete_suffix(".#{zone}") == name && %w[A AAAA CNAME].include?(row["type"]) }
        type = target.ipv4? ? "A" : "AAAA"
        raise Access::Denied, "Hostname has a conflicting DNS record" if records.any? { |row| row["type"] != type || IPAddr.new(row["data"]) != target }
        service.create_record!(name: name, type: type, data: target.to_s, ttl: 600) if records.empty?
      end
    end
  end
end
