require 'net/http'
require 'socket'
require 'ipaddr'
require 'json'
module LightekIdentity
  class PublicHttp
    class Invalid < StandardError; end
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 192.88.99.0/24 168.63.129.16/32 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96 fec0::/10 64:ff9b::/96 100::/64 2001:db8::/32 2001::/32 2001:2::/48 2002::/16].map { |v| IPAddr.new(v) }.freeze
    def self.json(url, form: nil, basic: nil, headers: {})
      uri = URI.parse(url)
      raise Invalid, 'Provider URL must use public HTTPS' unless uri.scheme == 'https' && uri.host && !uri.userinfo && !uri.fragment && uri.port == 443
      addresses = Addrinfo.getaddrinfo(uri.host,443,nil,:STREAM).map(&:ip_address).uniq
      raise Invalid, 'Provider address is not public' if addresses.empty? || addresses.any? { |a| BLOCKED.any? { |r| r.include?(IPAddr.new(a)) } }
      http = Net::HTTP.new(uri.host,443,nil)
      http.ipaddr = addresses.first
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      request = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      headers.each { |key,value| request[key] = value }
      request.set_form_data(form) if form
      request.basic_auth(*basic) if basic
      raw = +''
      http.request(request) do |response|
        raise Invalid, 'Identity provider request failed' unless response.is_a?(Net::HTTPSuccess)
        response.read_body do |part|
          raw << part
          raise Invalid, 'Provider response too large' if raw.bytesize > 1_000_000
        end
      end
      JSON.parse(raw)
    rescue URI::InvalidURIError, SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError
      raise Invalid, 'Identity provider is unavailable'
    end
  end
end
