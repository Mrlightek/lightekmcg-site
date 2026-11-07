require "net/http"
require "json"
require "jwt"
require "openssl"

module Gatekeeper
  module Hosting
    class GithubClient
      class Error < StandardError; end
      def initialize(payload)
        @payload = payload
      end

      def token
        @token ||= @payload["token"].presence || @payload["value"].presence || installation_token
      end

      def call(method, path, body: nil, bearer: nil, missing: false)
        raise Error, "Invalid GitHub API path" unless path.start_with?("/") && !path.match?(/[\r\n]/)
        uri = URI("https://api.github.com#{path}")
        request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
        request["Authorization"] = "Bearer #{bearer || token}"
        request["Accept"] = "application/vnd.github+json"
        request["Content-Type"] = "application/json"
        request["X-GitHub-Api-Version"] = "2022-11-28"
        request["User-Agent"] = "Lightek-Gatekeeper"
        request.body = JSON.generate(body) if body
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
        return nil if missing && response.code == "404"
        raise Error, "GitHub connection could not complete #{method.to_s.upcase} #{path.split('?').first} (HTTP #{response.code}). Check the connection's repository permissions." unless response.is_a?(Net::HTTPSuccess)
        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      rescue JSON::ParserError, SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
        raise Error, "GitHub connection is unavailable (#{error.class}); retry without changing saved credentials."
      end

      def installation_token
        id, pem = @payload.values_at("app_id", "private_key")
        raise Error, "Select a GitHub Vault credential containing token/value, or app_id and private_key." if id.blank? || pem.blank?
        jwt = JWT.encode({iat: Time.now.to_i - 30, exp: Time.now.to_i + 540, iss: id.to_s}, OpenSSL::PKey::RSA.new(pem), "RS256")
        installation = call(:get, "/repos/#{ImageBuilds::REPOSITORY}/installation", bearer: jwt)
        result = call(:post, "/app/installations/#{installation.fetch('id')}/access_tokens", bearer: jwt,
          body: {repositories: [ImageBuilds::REPOSITORY.split('/').last]})
        result.fetch("token")
      rescue OpenSSL::PKey::PKeyError, OpenSSL::PKey::RSAError
        raise Error, "The selected GitHub App private key could not be read. Verify its PEM formatting in Vault."
      ensure
        jwt&.clear
      end

      def close
        @token&.clear unless @token&.frozen?
        @payload.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      end
    end
  end
end
