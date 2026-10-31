require "net/http"
require "json"
require "uri"
require "digest"

module Gatekeeper
  module Compute
    module Providers
      module HttpSupport
        class RequestError < StandardError
          attr_reader :status
          def initialize(status, message)
            @status = status.to_i
            super(message)
          end
        end
        private

        def json_request(method:, url:, headers: {}, body: nil)
          uri = URI(url)
          klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method.to_sym)
          req = klass.new(uri)
          req["Accept"] = "application/json"
          req["Content-Type"] = "application/json"
          req["User-Agent"] = "Lightek-Gatekeeper-Compute"
          headers.each { |k, v| req[k] = v }
          req.body = JSON.generate(body) if body

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 45) { |http| http.request(req) }
          raise RequestError.new(res.code, "Provider HTTP #{res.code}: #{res.body.to_s.first(500)}") unless res.code.to_i.between?(200, 299)
          res.body.to_s.blank? ? nil : JSON.parse(res.body)
        rescue JSON::ParserError
          raise StandardError, "Provider returned invalid JSON"
        end
      end
    end
  end
end
