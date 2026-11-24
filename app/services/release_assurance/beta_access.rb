# frozen_string_literal: true

require "openssl"
require "base64"
require "net/http"

module ReleaseAssurance
  module BetaAccess
    def self.key_for(environment)
      Rails.application.key_generator.generate_key("release beta:#{environment.id}:#{environment.hostname}", 32).unpack1("H*")
    end

    def self.token_for(assignment, purpose:)
      environment = assignment.environment
      payload = {
        "assignment" => assignment.id, "hostname" => environment.hostname, "sha" => environment.candidate.source_sha,
        "purpose" => purpose, "until" => 2.minutes.from_now.to_i, "expires" => assignment.expires_at.to_i
      }
      encoded = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      "#{encoded}.#{signature(key_for(environment), encoded)}"
    end

    def self.verify!(token, hostname:, purpose:)
      key = ENV["LIGHTEK_RELEASE_ASSURANCE_BETA_KEY"]
      raise Policy::Denied unless ENV["LIGHTEK_RELEASE_ASSURANCE_TARGET"] == "1" && key&.match?(/\A[0-9a-f]{64}\z/)
      raise Policy::Denied unless token.is_a?(String) && token.bytesize <= 1024
      encoded, tag = token.split(".", 2)
      raise Policy::Denied unless encoded && tag && ActiveSupport::SecurityUtils.secure_compare(signature(key, encoded), tag)

      data = JSON.parse(Base64.urlsafe_decode64(encoded))
      unless data.fetch("hostname") == hostname && hostname == ENV["LIGHTEK_DEPLOYED_SITE_HOST"] &&
          data.fetch("sha") == Rails.application.config.x.fleet_boot_revision &&
          data.fetch("purpose") == purpose && Time.at(data.fetch("until")).future?
        raise Policy::Denied
      end
      data
    rescue JSON::ParserError, ArgumentError, KeyError
      raise Policy::Denied
    end

    def self.account!(data, revoke: false)
      expires = Time.at(data.fetch("expires"))
      raise Policy::Denied unless revoke || (expires.future? && expires <= 7.days.from_now)
      address = "beta-#{Integer(data.fetch('assignment'))}@example.test"
      # Concurrency is guarded by the User email unique index. Revocation
      # creates a suspended marker before any delayed sign-in can succeed.
      user = User.find_or_initialize_by(email_address: address)
      if user.new_record?
        user.assign_attributes(first_name: "Staging", last_name: "Tester", role: "client",
          password: SecureRandom.hex(32), staging_access_expires_at: expires)
        user.skip_password_setup_invitation = true
        user.access_suspended_at = Time.current if revoke
        user.save!
      end
      raise Policy::Denied unless user.role == "client" && user.staging_access_expires_at == expires
      if revoke
        user.update!(access_suspended_at: Time.current)
        user.sessions.delete_all
      end
      user
    end

    def self.revoke!(assignment)
      return if assignment.account_revoked_at || assignment.environment.state == "retired" || assignment.expires_at.past?
      hostname = Policy.hostname!(assignment.environment.hostname)
      uri = URI("https://#{hostname}/release-beta/account/revoke")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token_for(assignment, purpose: 'revoke')}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      raise Policy::Denied, "Temporary account revocation needs retry" unless response.is_a?(Net::HTTPSuccess)
      assignment.update!(account_revoked_at: Time.current)
    end

    def self.signature(key, encoded)
      OpenSSL::HMAC.hexdigest("SHA256", key, encoded)
    end
    private_class_method :signature
  end
end
