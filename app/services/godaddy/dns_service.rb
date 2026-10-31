require "net/http"
require "json"
require "uri"
require "securerandom"

module Godaddy
  class DnsService
    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    BASE_URL = "https://api.godaddy.com/v3/domains/zones".freeze
    TYPES = %w[A AAAA CAA CNAME MX NS SRV TXT].freeze

    def self.zones
      ENV.fetch("GODADDY_DOMAINS", "").split(",").map(&:strip).reject(&:blank?)
    end

    def initialize(zone:, domains: nil, token: nil)
      @zone = zone.to_s.downcase
      @configured_domains = domains.nil? ? self.class.zones : domains.to_s.split(",").map { |value| value.strip.downcase }.reject(&:blank?)
      @explicit_token = token.presence
      raise ConfigurationError, "Domain is not in managed DNS zones" unless @configured_domains.include?(@zone)
    end

    def records
      page = 1
      items = []

      loop do
        response = request(:get, "?page=#{page}&pageSize=100&totalRequired=true")
        raise ApiError, "Unexpected GoDaddy DNS response: #{response.class}" unless response.is_a?(Hash)

        page_items = response.fetch("items", [])
        raise ApiError, "Unexpected GoDaddy DNS items payload: #{page_items.class}" unless page_items.is_a?(Array)

        items.concat(page_items)

        total_pages = response["totalPages"].to_i
        break if total_pages <= page || page_items.empty?

        page += 1
      end

      items
    end
    def create_record!(attrs) = request(:post, "", body: normalize(attrs), idempotent: true)
    def update_record!(record_id, attrs) = request(:put, "/#{URI.encode_www_form_component(record_id.to_s)}", body: normalize(attrs), idempotent: true)

    def delete_record!(record_id)
      request(:delete, "/#{URI.encode_www_form_component(record_id.to_s)}", idempotent: true)
      true
    end

    private

    attr_reader :zone

    # Vault is authoritative whenever a GoDaddy secret exists. During migration,
    # the legacy environment token remains available only if no secret is stored.
    # Never fall back on an expired, disabled, or access-denied Vault secret.
    def token
      return @token if defined?(@token)

      return @token = @explicit_token if @explicit_token.present?

      slug = ENV.fetch("GODADDY_VAULT_SLUG", "godaddy-dns")
      if LightekVault::Secret.exists?(slug: slug)
        payload = LightekVault::Service.checkout!(
          slug: slug,
          consumer: self.class.name,
          purpose: "dns_management",
          requested_by: "network-control"
        )
        @token = payload.fetch("token").to_s.presence
      else
        @token = ENV["GODADDY_PAT"].presence
      end
      raise ConfigurationError, "GoDaddy DNS credential is not configured" if @token.blank?
      @token
    rescue LightekVault::Service::AccessDenied
      raise ConfigurationError, "GoDaddy DNS credential access denied by Vault"
    end

    def normalize(attributes)
      attrs = attributes.to_h.stringify_keys
      type = attrs.fetch("type").to_s.upcase
      raise ArgumentError, "Unsupported DNS type" unless TYPES.include?(type)

      body = {
        name: attrs.fetch("name").to_s,
        type: type,
        data: attrs.fetch("data").to_s,
        ttl: Integer(attrs["ttl"].presence || 600)
      }

      %w[priority weight port service protocol flag tag].each do |key|
        next if attrs[key].blank?
        body[key.to_sym] = %w[priority weight port].include?(key) ? Integer(attrs[key]) : attrs[key]
      end

      body
    end

    def request(method, suffix, body: nil, idempotent: false)
      uri = URI("#{BASE_URL}/#{URI.encode_www_form_component(zone)}/dns-records#{suffix}")
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["User-Agent"] = "Lightek-Network-Control"
      req["Idempotency-Key"] = SecureRandom.uuid if idempotent
      req.body = body.to_json if body

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
      raise ApiError, "GoDaddy HTTP #{res.code}" unless res.code.to_i.between?(200,299)
      return nil if res.body.to_s.blank?
      JSON.parse(res.body)
    end
  end
end
