require 'net/http'
require 'json'
require 'uri'
module LightekReservations
  module Federation
    class Client
      class Unavailable < StandardError; end
      CONSUMER = name.freeze
      def self.config(site) = site&.manifest.to_h&.fetch('lightek_reservation_federation', nil)
      def initialize(site)
        @site = site
        @config = self.class.config(site) || raise(Unavailable, 'This server is not connected to the reservation network')
        @origin = URI.parse(@config.fetch('origin'))
        raise Unavailable, 'Invalid reservation network origin' unless @origin.is_a?(URI::HTTPS) && @origin.host.present? && !@origin.userinfo && @origin.path.in?(['','/']) && !@origin.query && !@origin.fragment
      end
      def request(path, body: nil, method: :get)
        raise Unavailable, 'Invalid reservation operation' unless path.match?(%r{\A(?:catalog|offers|intents|reservations/[a-zA-Z0-9_-]{1,64}|payouts)\z})
        secret = LightekVault::Service.checkout!(slug: @config.fetch('credential_slug'), consumer: CONSUMER,
          purpose: 'reservation_federation', requested_by: 'reservation-network')
        uri = @origin.dup; uri.path = "/api/reservations/federation/#{path}"
        klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch}.fetch(method)
        request = klass.new(uri)
        request['Authorization'] = "Bearer #{secret.fetch('token')}"
        request['Accept'] = 'application/json'
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body) if body
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
        raise Unavailable, 'Reservation network returned an oversized response' if response.body.to_s.bytesize > 1_000_000
        data = JSON.parse(response.body)
        raise Unavailable, data['error'].to_s.presence || 'Reservation network is unavailable' unless response.is_a?(Net::HTTPSuccess)
        data
      rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise Unavailable, 'Reservation network is temporarily unavailable. Existing bookings are preserved.'
      ensure
        secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      end
      def synchronize_payouts!(merchant:)
        raise Unavailable, 'Payout connection belongs to another merchant' unless @site.tenant == merchant
        data = request('payouts')
        merchant.update!(stripe_connect_account_id: data['connect_account_id'],
          stripe_connect_details_submitted: data['connect_details_submitted'] == true,
          stripe_connect_payouts_enabled: data['connect_payouts_enabled'] == true)
        existing = LightekCommerce::PayoutSchedule.find_by(merchant: merchant)
        schedule = existing || LightekCommerce::PayoutSchedule.for!(merchant)
        schedule.with_lock do
          attributes = {cadence: data.fetch('cadence'), enabled: data.fetch('enabled')}
          if !existing || schedule.cadence != attributes[:cadence] || schedule.enabled? != attributes[:enabled]
            attributes[:next_run_at] = Time.iso8601(data.fetch('next_run_at'))
          end
          schedule.update!(attributes)
        end
        data
      end
      def checkout(attributes)
        data = request('intents', body: attributes, method: :post)
        # Remote responses cannot redirect users to a third-party origin.
        url = URI.parse(data.fetch('url'))
        raise Unavailable, 'Invalid checkout destination' unless url.scheme == @origin.scheme && url.host == @origin.host && url.port == @origin.port && url.path.match?(%r{\A/network/reservations/[0-9a-f]{64}\z}) && !url.userinfo
        url.to_s
      end
    end
  end
end
