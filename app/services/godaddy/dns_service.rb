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

    def initialize(zone:)
      @zone = zone.to_s.downcase
      raise ConfigurationError, "GODADDY_PAT is missing" if token.blank?
      raise ConfigurationError, "Domain is not in GODADDY_DOMAINS" unless self.class.zones.include?(@zone)
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

    def token = ENV["GODADDY_PAT"].presence

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
      raise ApiError, "GoDaddy HTTP #{res.code}: #{res.body}" unless res.code.to_i.between?(200,299)
      return nil if res.body.to_s.blank?
      JSON.parse(res.body)
    end
  end
end
