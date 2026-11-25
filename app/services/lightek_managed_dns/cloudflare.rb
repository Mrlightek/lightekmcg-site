require "net/http"
require "json"
require "resolv"
require "ipaddr"

module LightekManagedDns
  class Cloudflare
    class Unavailable < StandardError; end

    ROOT = "https://api.cloudflare.com/client/v4"
    ID = /\A[a-f0-9]{32}\z/

    def initialize(actor)
      @actor = actor
    end

    def zone!(id, domain)
      raise Unavailable, "Enter the Cloudflare zone ID." unless ID.match?(id.to_s)
      account = ENV["LIGHTEK_MANAGED_DNS_ACCOUNT_ID"]
      raise Unavailable, "The Lightek DNS provider account is not configured." unless ID.match?(account.to_s)

      zone = request("/zones/#{id}").fetch("result", {}).to_h
      unless zone["id"] == id && zone["name"] == domain && zone.dig("account", "id") == account && zone["type"] == "full"
        raise Unavailable, "The zone must match this domain and the configured Lightek Cloudflare account."
      end
      zone
    end

    def nameservers!(zone)
      settings = request("/zones/#{zone.fetch('id')}/dns_settings").fetch("result")
      setup = settings.fetch("nameservers")
      unless setup["type"] == "custom.account" && (1..5).cover?(setup["ns_set"]) && settings["multi_provider"] != true
        raise Unavailable, "Assign Lightek’s account nameserver set to the provider zone."
      end

      assigned = request("/accounts/#{zone.fetch('account').fetch('id')}/custom_ns").fetch("result")
      assigned = assigned.select { |server| server["ns_set"] == setup["ns_set"] }
      Resolv::DNS.open do |dns|
        dns.timeouts = [2, 3]
        assigned.map do |server|
          name = LightekSettings::SiteDomain.public_hostname!(server.fetch("ns_name"))
          expected = server.fetch("dns_records").map { |row| IPAddr.new(row.fetch("value")).to_s }.uniq.sort
          actual = dns.getaddresses("#{name}.").map { |ip| IPAddr.new(ip.to_s).to_s }.uniq.sort
          raise Unavailable, "Publish the provider’s addresses for each Lightek nameserver first." if expected.empty? || actual != expected

          name
        end
      end
    rescue KeyError, ArgumentError
      raise Unavailable, "The provider did not return a complete account nameserver set."
    end

    def records!(id)
      raise Unavailable, "The provider zone ID is invalid." unless ID.match?(id.to_s)

      (1..20).each_with_object([]) do |page, records|
        response = request("/zones/#{id}/dns_records?page=#{page}&per_page=100")
        rows = response.fetch("result")
        records.concat(rows.map { |row| row.slice("type", "name", "content", "data", "ttl", "priority", "proxied", "settings") })
        total = response.dig("result_info", "total_pages")
        return records if total ? page >= total : rows.size < 100
      end
      raise Unavailable, "This zone exceeds the Dashboard review limit."
    rescue KeyError, TypeError
      raise Unavailable, "The provider did not return the DNS zone records."
    end

    def close
      @token&.clear unless @token&.frozen?
      @token = nil
    end

    private

    def token
      @token ||= LightekVault::Service.checkout!(
        slug: ENV.fetch("LIGHTEK_MANAGED_DNS_VAULT_SLUG", "cloudflare-managed-dns"),
        consumer: self.class.name, purpose: "dns_management", requested_by: @actor.email_address
      ).fetch("token").to_s.dup
    rescue ActiveRecord::RecordNotFound, KeyError, LightekVault::Service::AccessDenied
      raise Unavailable, "Managed DNS provider access is unavailable."
    end

    def request(path)
      uri = URI("#{ROOT}#{path}")
      key = token
      raise Unavailable, "Managed DNS provider access is unavailable." if key.blank?

      message = Net::HTTP::Get.new(uri, {"Authorization" => "Bearer #{key}", "Accept" => "application/json"})
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 8) { |http| http.request(message) }
      body = JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      raise Unavailable, "The DNS provider could not verify this zone." unless body&.fetch("success", false)
      body
    rescue JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, "The DNS provider is temporarily unavailable."
    end
  end
end
