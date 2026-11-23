# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "timeout"

module LightekCommunications
  class VoipMs
    class Unavailable < StandardError; end

    API = URI("https://voip.ms/api/v1/rest.php").freeze
    SLUG = "communications-voip-ms"
    PURPOSE = "voice_carrier_verification"
    MAX_RESPONSE_BYTES = 128 * 1024
    SIP_ACCOUNT = /\A[0-9]{6}_[a-zA-Z0-9_-]{1,48}\z/
    NANP_NUMBER = /\A\+1[2-9][0-9]{2}[2-9][0-9]{6}\z/

    def self.save!(operator:, email:, password:)
      Fulfillment.check_operator!(operator)
      email = email.to_s.strip
      password = password.to_s
      unless email.bytesize <= 254 && URI::MailTo::EMAIL_REGEXP.match?(email) &&
          password.bytesize.between?(1, 256) && !password.match?(/[[:cntrl:]]/)
        raise Unavailable, "Enter the carrier account email and its API-specific password."
      end

      LightekVault::Service.store!(name: "Lightek Voice carrier API", slug: SLUG, provider: "voip_ms", purpose: PURPOSE,
        payload: { "email" => email, "password" => password },
        access_policy: { "consumers" => [name], "purposes" => [PURPOSE] }, requested_by: "user:#{operator.id}")
    rescue LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError, ActiveRecord::RecordInvalid
      raise Unavailable, "Vault could not save the voice carrier connection."
    end

    def self.configured?
      secret = LightekVault::Secret.find_by(slug: SLUG)
      secret && LightekVault::Policy.authorize(secret: secret, consumer: name, purpose: PURPOSE).allowed
    end

    def self.verify!(operator:, account:, phone_number: nil)
      Fulfillment.check_operator!(operator)
      account = account.to_s.strip
      phone_number = phone_number.to_s.strip.presence
      unless SIP_ACCOUNT.match?(account) && (phone_number.nil? || NANP_NUMBER.match?(phone_number))
        raise Unavailable, "Enter a VoIP.ms SIP subaccount and a North American public phone number."
      end

      credentials = LightekVault::Service.checkout!(slug: SLUG, consumer: name, purpose: PURPOSE, requested_by: "user:#{operator.id}")
      new(credentials).verify!(account: account, phone_number: phone_number)
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied,
        LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError
      raise Unavailable, "Connect the voice carrier in Vault before verifying activation."
    end

    def initialize(credentials)
      @credentials = credentials
    end

    def verify!(account:, phone_number: nil)
      verify_route!(account: account, phone_number: phone_number) if phone_number
      registration = fetch!("getRegistrationStatus", account: account)
      raise Unavailable, "The carrier did not confirm that the SIP subaccount is registered." unless registration["registered"] == "yes"

      { "carrier" => "voip_ms", "carrier_verified_at" => Time.current.iso8601 }
    end

    private

    def verify_route!(account:, phone_number:)
      did = phone_number.delete_prefix("+1")
      inventory = fetch!("getDIDsInfo", did: did).fetch("dids", [])
      return if inventory.is_a?(Array) && inventory.any? { |row| row.is_a?(Hash) && row["did"].to_s == did && row["routing"] == "account:#{account}" }

      raise Unavailable, "The carrier did not confirm this number routes to the selected SIP subaccount."
    end

    def fetch!(method, **parameters)
      query = URI.encode_www_form(parameters.merge(method: method, content_type: "json",
        api_username: @credentials.fetch("email"), api_password: @credentials.fetch("password")))
      # The carrier authenticates in the HTTPS query. Use a fixed origin, no proxy
      # or redirects, and never propagate the request target or response body.
      request = Net::HTTP::Get.new("#{API.path}?#{query}")
      http = Net::HTTP.new(API.host, API.port, nil)
      http.use_ssl = true
      http.open_timeout = 4
      http.read_timeout = 4
      http.max_retries = 0

      body = +""
      Timeout.timeout(12) do
        http.start do |connection|
          connection.request(request) do |response|
            raise Unavailable, "The carrier lookup failed." unless response.is_a?(Net::HTTPSuccess)

            response.read_body do |chunk|
              raise Unavailable, "The carrier returned an oversized response." if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
              body << chunk
            end
          end
        end
      end
      payload = JSON.parse(body)
      raise Unavailable, "The carrier rejected the lookup. Check the API connection and its IP allowlist." unless payload.is_a?(Hash) && payload["status"] == "success"

      payload
    rescue IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, JSON::ParserError, KeyError
      raise Unavailable, "The carrier lookup could not be completed."
    end
  end
end
