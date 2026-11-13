require "net/http"
require "resolv"
require "ipaddr"
module LightekConnect
  class InstanceTransport
    class Unavailable < StandardError; end
    FORBIDDEN = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96].map { |range| IPAddr.new(range) }.freeze
    def self.rename!(peer:, connection:, name:)
      raise Gatekeeper::Hosting::Access::Denied, "Client instance is unavailable" unless peer.active?
      host = LightekSettings::SiteDomain.public_hostname!(peer.site.host)
      addresses = Resolv.getaddresses(host)
      raise Unavailable, "Client instance address is unavailable" if addresses.empty? || addresses.any? { |address| FORBIDDEN.any? { |range| range.include?(IPAddr.new(address)) } }
      secret = LightekVault::Service.checkout!(slug: "reservation-peer-#{peer.key}", consumer: LightekReservations::Federation::Issuer::CONSUMER,
        purpose: "reservation_federation", requested_by: connection.user.email_address)
      uri = URI("https://#{host}/api/connect/instance/site")
      request = Net::HTTP::Patch.new(uri)
      request["Authorization"] = "Bearer #{secret.fetch('token')}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(connection_id: connection.id, name: name)
      http = Net::HTTP.new(host, 443, nil)
      http.ipaddr = addresses.first
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 20
      response = http.start { |session| session.request(request) }
      raise Unavailable, "Client instance did not confirm the save" unless response.is_a?(Net::HTTPSuccess) && response.body.bytesize < 100_000
      data = JSON.parse(response.body)
      raise Unavailable, "Client instance verification failed" unless data["host"] == host && data["verified"] == true && data["name"] == name.to_s.strip
      data
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Resolv::ResolvError
      raise Unavailable, "Client instance is temporarily unavailable"
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end
  end
end
