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

      for_operator(operator).verify!(account: account, phone_number: phone_number)
    end

    def self.for_operator(operator)
      Fulfillment.check_operator!(operator)
      connect("user:#{operator.id}")
    end

    def self.for_paid_voice(order_id)
      connect("paid-voice:#{order_id}")
    end

    def self.connect(requested_by)
      credentials = LightekVault::Service.checkout!(slug: SLUG, consumer: name, purpose: PURPOSE, requested_by: requested_by)
      new(credentials)
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied,
        LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError
      raise Unavailable, "Connect the voice carrier in Vault before verifying activation."
    end

    private_class_method :connect

    def initialize(credentials)
      @credentials = credentials
    end

    def verify!(account:, phone_number: nil)
      verify_route!(account: account, phone_number: phone_number) if phone_number
      registration = fetch!("getRegistrationStatus", account: account)
      raise Unavailable, "The carrier did not confirm that the SIP subaccount is registered." unless registration["registered"] == "yes"

      { "carrier" => "voip_ms", "carrier_verified_at" => Time.current.iso8601 }
    end

    def search_numbers!(area_code:)
      numbers = fetch!("searchDIDsUSA", type: "starts", query: area_code, success: %w[success no_dids no_did no_numbers])["dids"]
      Array(numbers).filter_map do |row|
        if row.is_a?(Hash) && NANP_NUMBER.match?("+1#{row["did"]}")
          row.slice("did", "ratecenter", "perminute_setup", "perminute_monthly", "flat_setup", "flat_monthly")
        end
      end.first(20)
    end

    def order_number!(did:, routing:, pop:, billing_type:)
      fetch!("orderDID", did: did, routing: routing, pop: pop, billing_type: billing_type, dialtime: 60, cnam: 0)
    end

    def verify_portability!(did)
      result = fetch!("getPortability", did: did)
      unless %w[1 yes true].include?(result["portable"].to_s.downcase)
        raise Unavailable, "VoIP.ms did not confirm that this number can be ported."
      end
    end

    def port_number!(did:, fields:)
      fetch!("addLNPPort", **fields.merge(numbers: did, portType: 1, country: "US"))
    end

    def port_status!(reference)
      fetch!("getLNPStatus", portid: reference)
    end

    def attach_port_file!(reference, base64_document)
      fetch!("addLNPFile", post: true, portid: reference, file: base64_document)
    end

    def number_on_account?(did)
      rows = fetch!("getDIDsInfo", did: did, success: %w[success no_did no_dids no_numbers])["dids"]
      rows.is_a?(Array) && rows.any? { |row| row.is_a?(Hash) && row["did"].to_s == did }
    end

    def route_port!(did:, account:, pop:)
      inventory = fetch!("getDIDsInfo", did: did).fetch("dids", [])
      unless inventory.is_a?(Array) && inventory.any? { |row| row.is_a?(Hash) && row["did"].to_s == did }
        raise Unavailable, "The ported number is not yet present in your VoIP.ms inventory."
      end
      fetch!("setDIDPOP", did: did, pop: pop)
      fetch!("setDIDRouting", did: did, routing: "account:#{account}")
      verify_route!(account: account, phone_number: "+1#{did}")
    end

    def validate_e911!(did:, account:, fields:)
      verify_route!(account: account, phone_number: "+1#{did}")
      fetch!("e911Validate", **fields.merge(did: did, country: "US"))
    end

    def provision_e911!(did:, fields:)
      fetch!("e911Provision", **fields.merge(did: did, country: "US"))
      info = fetch!("e911Info", did: did)["info"]
      unless info.is_a?(Hash) && info["did"].to_s == did && info["street_number"].to_s == fields[:street_number].to_s &&
          info["state"].to_s.casecmp?(fields[:state]) && info["zip"].to_s.first(5) == fields[:zip].first(5)
        raise Unavailable, "VoIP.ms did not confirm the submitted E911 address."
      end
    end

    private

    def verify_route!(account:, phone_number:)
      did = phone_number.delete_prefix("+1")
      inventory = fetch!("getDIDsInfo", did: did).fetch("dids", [])
      return if inventory.is_a?(Array) && inventory.any? { |row| row.is_a?(Hash) && row["did"].to_s == did && row["routing"] == "account:#{account}" }

      raise Unavailable, "The carrier did not confirm this number routes to the selected SIP subaccount."
    end

    def fetch!(method, post: false, success: ["success"], **parameters)
      fields = parameters.merge(method: method, content_type: "json", api_username: @credentials.fetch("email"),
        api_password: @credentials.fetch("password"))
      # Use a fixed HTTPS origin and never propagate the request target or response body.
      request = if post
        Net::HTTP::Post.new(API.path).tap { |message| message.set_form(fields.to_a, "multipart/form-data") }
      else
        Net::HTTP::Get.new("#{API.path}?#{URI.encode_www_form(fields)}")
      end
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
      raise Unavailable, "The carrier rejected the lookup. Check the API connection and its IP allowlist." unless payload.is_a?(Hash) && success.include?(payload["status"])

      payload
    rescue IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, JSON::ParserError, KeyError
      raise Unavailable, "The carrier lookup could not be completed."
    end
  end
end
