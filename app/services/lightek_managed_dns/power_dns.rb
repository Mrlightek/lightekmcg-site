require "ipaddr"
require "json"
require "net/http"
require "resolv"
require "uri"

module LightekManagedDns
  class PowerDns
    class Unavailable < StandardError; end
    EDITABLE_TYPES = %w[A AAAA CAA CNAME MX SRV TXT].freeze
    ZONES = "/api/v1/servers/localhost/zones"
    UNUSABLE_ENDPOINTS = %w[0.0.0.0/8 100.64.0.0/10 224.0.0.0/3 ::/128 ff00::/8].map { |range| IPAddr.new(range) }.freeze

    def initialize(actor)
      @actor = actor
    end

    def zone!(id, domain)
      unless id == domain && LightekSettings::SiteDomain.public_hostname?(domain)
        raise Unavailable, "The PowerDNS zone must match the enrolled domain."
      end
      zone = request(Net::HTTP::Get, zone_path(id))
      unless zone.is_a?(Hash) && zone["name"] == "#{domain}." &&
          %w[Primary Master].include?(zone["kind"]) && zone["rrsets"].is_a?(Array)
        raise Unavailable, "Import this zone into the Lightek DNS primary first."
      end
      zone
    end

    def records!(id, zone: zone!(id, id))
      sets = zone.fetch("rrsets")
      rows = sets.reject { |set| set["type"] == "SOA" }.flat_map do |set|
        set.fetch("records").map do |record|
          {"name" => set.fetch("name").delete_suffix("."), "type" => set.fetch("type"), "ttl" => set.fetch("ttl"),
            "content" => record.fetch("content"), "disabled" => record.fetch("disabled"), "proxied" => false}
        end
      end
      raise Unavailable, "This zone exceeds the Dashboard review limit." if rows.size > 2_000
      rows
    rescue ArgumentError, KeyError, TypeError
      raise Unavailable, "The DNS primary returned an incomplete zone."
    end

    def nameservers!(zone)
      domain = zone.fetch("name").delete_suffix(".")
      records!(domain, zone: zone).select do |record|
        record["type"] == "NS" && record["name"] == domain && !record["disabled"]
      end.pluck("content")
    end

    def verify_authority!(zone, nameservers:, website:, ip:)
      domain = zone.fetch("name")
      serial = zone["edited_serial"] || zone["serial"]
      raise Unavailable, "The DNS primary did not return a zone serial." unless serial.is_a?(Integer)
      map = public_endpoints!(nameservers)
      map.each do |name, endpoints|
        actual = Resolv::DNS.open do |dns|
          dns.timeouts = [2]
          dns.getaddresses("#{name}.").map { |address| IPAddr.new(address.to_s).to_s }.uniq.sort
        end
        raise Unavailable, "Publish the configured DNS addresses for #{name} first." unless actual == endpoints.sort

        endpoints.each do |endpoint|
          soa = DnsProbe.answers(endpoint, domain, Resolv::DNS::Resource::IN::SOA)
          ns = DnsProbe.answers(endpoint, domain, Resolv::DNS::Resource::IN::NS)
          web4 = DnsProbe.answers(endpoint, "#{website}.", Resolv::DNS::Resource::IN::A)
          web6 = DnsProbe.answers(endpoint, "#{website}.", Resolv::DNS::Resource::IN::AAAA)
          unless soa.map(&:serial) == [serial] && ns.map { |record| record.name.to_s.downcase }.uniq.sort == nameservers &&
              (web4 + web6).map { |record| record.address.to_s }.uniq == [ip]
            raise Unavailable, "#{name} has not replicated the reviewed zone and website address yet."
          end
        end
      end
    rescue DnsProbe::Unavailable
      raise Unavailable, "An assigned nameserver did not return an authoritative DNS answer."
    end

    def write_rrset!(domain:, name:, type:, ttl:, contents:, remove:)
      raise Unavailable, "Choose a supported DNS record type." unless EDITABLE_TYPES.include?(type)

      rrset = {"name" => "#{name}.", "type" => type, "changetype" => remove ? "DELETE" : "REPLACE"}
      unless remove
        rrset["ttl"] = ttl
        rrset["records"] = contents.map { |content| {"content" => content, "disabled" => false} }
      end
      path = zone_path(domain)
      request(Net::HTTP::Patch, path, {"rrsets" => [rrset]})
      notify_secondaries(path)
    end

    def close
      @key&.clear
      @key = nil
    end

    private

    def notify_secondaries(path)
      request(Net::HTTP::Put, "#{path}/notify")
      :notified
    rescue Unavailable
      :awaiting_refresh
    end

    def public_endpoints!(nameservers)
      values = JSON.parse(ENV.fetch("LIGHTEK_POWERDNS_PUBLIC_ENDPOINTS", "{}"))
      unless values.is_a?(Hash) && values.keys.sort == nameservers
        raise Unavailable, "Configure a public DNS endpoint for each Lightek nameserver."
      end
      addresses = values.transform_values do |ips|
        raise ArgumentError unless ips.is_a?(Array) && ips.size.between?(1, 2)

        ips.map do |value|
          raise ArgumentError unless value.is_a?(String) && !value.include?("/")
          address = IPAddr.new(value).native
          raise ArgumentError if address.private? || address.loopback? || address.link_local? ||
            UNUSABLE_ENDPOINTS.any? { |range| range.include?(address) }
          address.to_s
        end
      end
      unless addresses.values.flatten.uniq.size == addresses.values.flatten.size
        raise Unavailable, "Public nameservers must use distinct addresses."
      end
      addresses
    rescue JSON::ParserError, ArgumentError
      raise Unavailable, "The configured public DNS addresses are invalid."
    end

    def zone_path(domain)
      raise Unavailable, "The zone name is invalid." unless LightekSettings::SiteDomain.public_hostname?(domain) && domain == domain.downcase.delete_suffix(".")
      "#{ZONES}/#{domain}."
    end

    def endpoint
      uri = URI.parse(ENV.fetch("LIGHTEK_POWERDNS_API_URL", ""))
      loopback = %w[127.0.0.1 ::1].include?(uri.hostname)
      unless (uri.is_a?(URI::HTTPS) || (uri.is_a?(URI::HTTP) && loopback)) && uri.host.present? &&
          uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.in?(["", "/"])
        raise Unavailable, "Configure the private PowerDNS HTTPS endpoint."
      end
      uri
    rescue URI::InvalidURIError
      raise Unavailable, "The configured PowerDNS API URL is invalid."
    end

    def key
      @key ||= LightekVault::Service.checkout!(
        slug: ENV.fetch("LIGHTEK_POWERDNS_VAULT_SLUG", "lightek-powerdns"),
        consumer: self.class.name, purpose: "dns_management", requested_by: @actor.email_address
      ).fetch("api_key").to_s.dup
    rescue ActiveRecord::RecordNotFound, KeyError, LightekVault::Service::AccessDenied
      raise Unavailable, "PowerDNS API credentials are unavailable."
    end

    def request(method, path, body = nil)
      uri = endpoint
      raise Unavailable, "PowerDNS API credentials are unavailable." if key.blank?

      message = method.new(path, {"X-API-Key" => key, "Accept" => "application/json"})
      if body
        message["Content-Type"] = "application/json"
        message.body = JSON.generate(body)
      end
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 5
      http.write_timeout = 5
      http.max_retries = 0
      response = http.start { |client| client.request(message) }
      unless response.is_a?(Net::HTTPSuccess)
        if response.is_a?(Net::HTTPNotFound)
          raise Unavailable, "The enrolled zone is missing from the PowerDNS primary."
        end
        raise Unavailable, "PowerDNS rejected this request (HTTP #{response.code})."
      end
      return if response.is_a?(Net::HTTPNoContent)
      JSON.parse(response.body)
    rescue JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, "PowerDNS is temporarily unavailable. Reload the zone before retrying a change."
    end
  end
end
