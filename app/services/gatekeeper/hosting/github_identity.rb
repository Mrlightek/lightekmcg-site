require "jwt"
require "json"
require "net/http"
module Gatekeeper
  module Hosting
    class GithubIdentity
      class Invalid < StandardError; end
      ISSUER = "https://token.actions.githubusercontent.com".freeze
      JWKS_URL = "#{ISSUER}/.well-known/jwks".freeze

      def self.verify!(token:, identity:)
        raise Invalid, "Image build identity is not configured" if identity.blank? || token.to_s.bytesize > 16_384
        claims, = JWT.decode(token, nil, true, algorithms: ["RS256"], jwks: trusted_keys,
          verify_iss: true, iss: ISSUER, verify_aud: true, aud: identity.fetch("audience"),
          verify_iat: false, leeway: 30, required_claims: %w[exp iat nbf aud iss repository_id repository sha workflow_sha workflow_ref event_name run_id])
        raise Invalid, "Image callback issue time is invalid" unless claims["iat"].is_a?(Numeric) && claims["iat"] <= Time.now.to_i + 30
        primary = "#{ImageBuilds::REPOSITORY}/.github/workflows/"
        workflow = claims["workflow_ref"].to_s
        correct_workflow = workflow.start_with?("#{primary}application-image.yml@") ||
          (workflow.start_with?("#{primary}customer-release.yml@") &&
            claims["job_workflow_ref"].to_s.start_with?("#{primary}application-image.yml@") && claims["job_workflow_sha"] == identity.fetch("source_sha"))
        unless claims["repository"] == ImageBuilds::REPOSITORY && claims["repository_id"].to_s == identity.fetch("repository_id").to_s &&
            claims["sha"] == identity.fetch("source_sha") && claims["workflow_sha"] == identity.fetch("source_sha") &&
            correct_workflow && claims["event_name"] == "workflow_dispatch" &&
            claims["run_id"].to_s.match?(/\A[0-9]+\z/) && (identity["run_id"].blank? || identity["run_id"].to_s == claims["run_id"].to_s)
          raise Invalid, "Image callback does not match its authorized build"
        end
        claims
      rescue JWT::DecodeError, KeyError, TypeError, ArgumentError
        raise Invalid, "Image callback identity could not be verified"
      end

      def self.trusted_keys
        Rails.cache.fetch("gatekeeper/github-oidc-jwks", expires_in: 5.minutes) do
          uri = URI(JWKS_URL)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri) }
          raise Invalid, "GitHub identity keys are unavailable" unless response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        end
      end
    end
  end
end
