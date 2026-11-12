require "net/http"
require "json"
require "uri"
require "bigdecimal"
module LightekShipping
  class Fedex
    class Unavailable < StandardError; end
    CONSUMER = name.freeze
    def initialize(account:)
      @account = account
      raise Unavailable, "FedEx shipping is not enabled" unless account.enabled? && (account.sandbox? || account.production_approved?)
      @origin = account.sandbox? ? "https://apis-sandbox.fedex.com" : "https://apis.fedex.com"
    end
    def with_credentials
      @credentials = LightekVault::Service.checkout!(slug: @account.credential_slug, consumer: CONSUMER,
        purpose: "carrier_shipping", requested_by: "platform-shipping")
      yield
    ensure
      @credentials&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      @credentials = nil
    end
    def account_number = @credentials.fetch("account_number")
    def rates(payload)
      with_credentials do
        shipment = payload.deep_dup
        shipment["recipient"] = shipment.delete("recipients").sole
        shipment["shipDateStamp"] = Date.current.iso8601
        response = request(:post, "/rate/v1/rates/quotes", {"accountNumber" => {"value" => account_number}, "rateRequestControlParameters" => {"returnTransitTimes" => true}, "requestedShipment" => shipment})
        Array(response.dig("output", "rateReplyDetails")).filter_map do |service|
          details = Array(service["ratedShipmentDetails"])
          rated = details.find { |row| row["rateType"].to_s.include?("ACCOUNT") }
          next unless rated
          amount = rated["totalNetCharge"]
          currency = amount.is_a?(Hash) ? amount["currency"] : rated["currency"]
          next unless currency.to_s.upcase == "USD"
          amount = amount["amount"] if amount.is_a?(Hash)
          cents = (BigDecimal(amount.to_s) * 100).ceil
          next unless cents.positive?
          {"service_code" => service.fetch("serviceType"), "service_name" => service["serviceName"].presence || service.fetch("serviceType").humanize, "cost_cents" => cents}
        end
      end
    end
    def ship(payload, reference:)
      with_credentials do
        shipment = payload.deep_dup
        shipment["shippingChargesPayment"] = {"paymentType" => "THIRD_PARTY", "payor" => {"responsibleParty" => {"accountNumber" => {"value" => account_number}, "address" => {"countryCode" => "US"}}}}
        shipment["labelSpecification"] = {"imageType" => "PDF", "labelStockType" => "PAPER_4X6"}
        request(:post, "/ship/v1/shipments", {"accountNumber" => {"value" => account_number}, "labelResponseOptions" => "LABEL", "requestedShipment" => shipment}, reference: reference)
      end
    end
    def track(number)
      with_credentials { request(:post, "/track/v1/trackingnumbers", {"includeDetailedScans" => true, "trackingInfo" => [{"trackingNumberInfo" => {"trackingNumber" => number}}]}) }
    end
    def cancel(number)
      with_credentials { request(:put, "/ship/v1/shipments/cancel", {"accountNumber" => {"value" => account_number}, "trackingNumber" => number, "deletionControl" => "DELETE_ALL_PACKAGES", "senderCountryCode" => "US"}) }
    end
    def token
      key = "lightek-fedex-oauth-#{@account.id}-#{@account.updated_at.to_i}-#{@account.sandbox?}"
      Rails.cache.fetch(key, expires_in: 55.minutes) do
        params = {grant_type: @credentials.fetch("grant_type", "client_credentials"), client_id: @credentials.fetch("client_id"), client_secret: @credentials.fetch("client_secret")}
        params[:child_key] = @credentials["child_key"] if @credentials["child_key"].present?
        params[:child_secret] = @credentials["child_secret"] if @credentials["child_secret"].present?
        uri = URI("#{@origin}/oauth/token")
        req = Net::HTTP::Post.new(uri); req.set_form_data(params)
        data = perform(uri, req)
        data.fetch("access_token")
      end
    end
    def request(method, path, payload, reference: nil)
      uri = URI("#{@origin}#{path}")
      req = {post: Net::HTTP::Post, put: Net::HTTP::Put}.fetch(method).new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req["x-locale"] = "en_US"
      req["x-customer-transaction-id"] = reference if reference
      req.body = JSON.generate(payload)
      perform(uri, req)
    end
    def perform(uri, req)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 45) { |http| http.request(req) }
      raise Unavailable, "Carrier response exceeded the permitted size" if response.body.to_s.bytesize > 20.megabytes
      raise Unavailable, "FedEx could not confirm this request (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
      raise Unavailable, "FedEx did not confirm the operation (#{error.class})"
    end
  end
end
