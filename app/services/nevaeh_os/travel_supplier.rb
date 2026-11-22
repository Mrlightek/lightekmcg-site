require 'net/http'
require 'json'
require 'digest'
require 'openssl'

module NevaehOs
  class TravelSupplier
    class Unavailable < StandardError; end
    class Uncertain < Unavailable; end
    PURPOSE = 'executive_travel'
    ORIGIN = 'https://api.duffel.com'.freeze

    def initialize(owner, device_ip: nil, device_agent: nil)
      @owner = owner
      @device_ip = device_ip
      @device_agent = device_agent
    end

    def self.slug(owner) = "executive-travel-#{owner.id}"

    def self.configure!(owner, token)
      raise ArgumentError, 'Enter a Duffel test or live access token.' unless token.to_s.match?(/\Aduffel_(?:test|live)_[a-zA-Z0-9_-]{12,200}\z/)

      LightekVault::Service.store!(name: 'Executive travel booking', slug: slug(owner), payload: {'token'=>token},
        purpose: PURPOSE, provider: 'duffel', access_policy: {'consumers'=>[name], 'purposes'=>[PURPOSE]}, requested_by: owner.email_address)
    end

    def search_flights(origin:, destination:, departure:, returning:)
      origin, destination = [origin, destination].map { |code| code.to_s.strip.upcase }
      unless [origin, destination].all? { |code| code.match?(/\A[A-Z]{3}\z/) } && origin != destination
        raise ArgumentError, 'Enter two distinct three-letter airport codes.'
      end
      start = travel_date(departure)
      finish = travel_date(returning) if returning.present?
      raise ArgumentError, 'Return must be on or after departure.' if finish && finish < start

      slices = [{origin: origin, destination: destination, departure_date: start.iso8601}]
      slices << {origin: destination, destination: origin, departure_date: finish.iso8601} if finish
      data = request(:post, '/air/offer_requests?return_offers=true', {slices: slices, passengers: [{type: 'adult'}]})
      Array(data['offers']).first(25).map do |offer|
        {id: offer['id'], label: itinerary(offer).join(' / '), total: "#{offer['total_amount']} #{offer['total_currency']}"}
      end
    end

    def search_hotels(latitude:, longitude:, check_in:, check_out:)
      lat = Float(latitude, exception: false)
      lon = Float(longitude, exception: false)
      unless lat&.between?(-90, 90) && lon&.between?(-180, 180)
        raise ArgumentError, 'Enter valid decimal latitude and longitude.'
      end
      start = travel_date(check_in)
      finish = travel_date(check_out)
      raise ArgumentError, 'Checkout must be after check-in and within 30 nights.' unless finish > start && finish <= start + 30

      data = request(:post, '/stays/search', {rooms: 1, guests: [{type: 'adult'}], check_in_date: start.iso8601,
        check_out_date: finish.iso8601, location: {geographic_coordinates: {latitude: lat, longitude: lon}, radius: 10}})
      Array(data['results']).first(25).map do |stay|
        {id: stay['id'], label: stay.dig('accommodation', 'name'),
          total: "#{stay['cheapest_rate_total_amount']} #{stay['cheapest_rate_total_currency'] || stay['cheapest_rate_public_currency']}"}
      end
    end

    def hotel_rates(id)
      validate_id!(id, 'srr')
      data = request(:post, "/stays/search_results/#{id}/actions/fetch_all_rates")
      Array(data.dig('accommodation', 'rooms')).flat_map do |room|
        Array(room['rates']).map do |rate|
          {id: rate['id'], label: [data.dig('accommodation', 'name'), room['name']].compact.join(' · '),
            total: "#{rate['total_amount']} #{rate['total_currency']}"}
        end
      end.first(30)
    end

    def quote(kind, id)
      case kind
      when 'flight'
        validate_id!(id, 'off')
        data = request(:get, "/air/offers/#{id}")
        {id: data.fetch('id'), amount: data.fetch('total_amount'), currency: data.fetch('total_currency'),
          expires_at: data.fetch('expires_at'), mode: data.fetch('lightek_mode'), passenger_ids: data.fetch('passengers').map { |passenger| passenger.fetch('id') },
          itinerary: itinerary(data)}
      when 'hotel'
        validate_id!(id, 'rat')
        data = request(:post, '/stays/quotes', {rate_id: id})
        {id: data.fetch('id'), amount: data.fetch('total_amount'), currency: data.fetch('total_currency'),
          mode: data.fetch('lightek_mode'), guest_count: Array(data['guests']).size, property: data.dig('accommodation', 'name'),
          check_in: data['check_in_date'], check_out: data['check_out_date'],
          due_at_property: data['due_at_accommodation_amount'], property_currency: data['due_at_accommodation_currency']}
      else
        raise ArgumentError, 'Choose flight or hotel.'
      end
    end

    def verify(booking, id)
      prefix = booking.kind == 'flight' ? 'ord' : 'bok'
      validate_id!(id, prefix)
      path = booking.kind == 'flight' ? "/air/orders/#{id}" : "/stays/bookings/#{id}"
      confirm(booking, request(:get, path))
    end

    def book(booking, person)
      quote = booking.quote
      contact = person.slice('given_name', 'family_name', 'email', 'phone_number')
      metadata = {lightek_booking: identifier(booking)}
      if booking.kind == 'flight'
        passengers = [contact.merge(person.slice('title', 'gender', 'born_on')).merge(id: quote.fetch('passenger_ids').sole)]
        data = request(:post, '/air/orders', {type: 'instant', selected_offers: [quote.fetch('id')], passengers: passengers,
          payments: [{type: 'balance', amount: booking.amount, currency: booking.currency}], metadata: metadata}, purchase: true, expected_mode: quote['mode'])
      else
        data = request(:post, '/stays/bookings', {quote_id: quote.fetch('id'), email: contact.fetch('email'),
          phone_number: contact.fetch('phone_number'), guests: [contact.slice('given_name', 'family_name')], metadata: metadata}, purchase: true, expected_mode: quote['mode'])
      end
      confirm(booking, data)
    end

    private

    def itinerary(offer)
      offer.fetch('slices').flat_map do |slice|
        slice.fetch('segments').map do |segment|
          "#{segment.dig('origin', 'iata_code')} → #{segment.dig('destination', 'iata_code')} · #{segment['departing_at']} · #{segment.dig('operating_carrier', 'name')}"
        end
      end
    end

    def travel_date(value)
      date = Date.iso8601(value.to_s)
      raise ArgumentError, 'Choose a travel date from today onward.' if date.past?

      date
    rescue Date::Error
      raise ArgumentError, 'Enter a valid travel date.'
    end

    def identifier(booking)
      "lightek-#{Digest::SHA256.hexdigest([booking.id, booking.created_at.iso8601(6)].join(':')).first(32)}"
    end

    def confirm(booking, data)
      reference = booking.kind == 'flight' ? data['booking_reference'] : data['reference']
      confirmed = booking.kind == 'flight' ? data.dig('payment_status', 'paid_at').present? : data['status'] == 'confirmed'
      matching_mode = booking.quote['mode'].nil? || data['lightek_mode'] == booking.quote['mode']
      unless matching_mode && data.dig('metadata', 'lightek_booking') == identifier(booking) && confirmed && reference.present? && data['id'].present?
        raise Uncertain, 'The supplier has not returned a matching confirmed reservation. Reconcile the booking before retrying.'
      end

      {supplier_id: data.fetch('id'), reference: reference}
    end

    def validate_id!(value, prefix)
      raise ArgumentError, "Enter a valid supplier #{prefix} ID." unless value.to_s.match?(/\A#{prefix}_[a-zA-Z0-9]{10,40}\z/)
    end

    def request(method, path, data = nil, purchase: false, expected_mode: nil)
      credentials = LightekVault::Service.checkout!(slug: self.class.slug(@owner), consumer: self.class.name,
        purpose: PURPOSE, requested_by: @owner.email_address)
      token = credentials['token']
      raise Unavailable, 'The connected supplier credential is incomplete.' if token.blank?
      mode = token.start_with?('duffel_live_') ? 'live' : 'test'
      raise Unavailable, 'The quote belongs to a different supplier mode. Refresh it.' if expected_mode && expected_mode != mode

      uri = URI.parse("#{ORIGIN}#{path}")
      message = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      message['Authorization'] = "Bearer #{token}"
      message['Duffel-Version'] = 'v2'
      message['Content-Type'] = 'application/json'
      message['Accept'] = 'application/json'
      message['X-Duffel-Device-IP'] = @device_ip if @device_ip.present?
      message['X-Duffel-Device-User-Agent'] = @device_agent if @device_agent.present?
      message.body = JSON.generate(data: data) if data
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 135) do |http|
        http.max_retries = 0
        http.request(message)
      end
      if response.is_a?(Net::HTTPSuccess) && (!purchase || response.code == '201')
        value = JSON.parse(response.body).fetch('data')
        raise KeyError unless value.is_a?(Hash)

        return value.merge('lightek_mode'=>mode)
      end

      request_id = response['x-request-id'].to_s.gsub(/[^a-zA-Z0-9_-]/, '').first(80)
      if purchase && !%w[400 401 403 404 422 429].include?(response.code)
        raise Uncertain, "Booking outcome needs reconciliation. Supplier request #{request_id.presence || 'unavailable'}."
      end
      raise Unavailable, "Supplier request was rejected (HTTP #{response.code})."
    rescue LightekVault::Service::AccessDenied
      raise Unavailable, 'Connect the supplier in the executive travel workspace.'
    rescue JSON::ParserError, IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, KeyError
      raise(purchase ? Uncertain : Unavailable, purchase ? 'Booking outcome unknown. Reconcile with the supplier.' : 'Travel supplier response is unavailable.')
    ensure
      token&.clear if token.is_a?(String) && !token.frozen?
    end
  end
end
