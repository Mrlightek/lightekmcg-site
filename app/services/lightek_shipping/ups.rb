# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'bigdecimal'
require 'securerandom'

module LightekShipping
  class Ups
    class Unavailable < StandardError; end
    CONSUMER = name.freeze
    VERSION = 'v2409'
    SERVICES = {'01' => 'Next Day Air', '02' => '2nd Day Air', '03' => 'Ground', '12' => '3 Day Select',
      '13' => 'Next Day Air Saver', '14' => 'Next Day Air Early', '59' => '2nd Day Air A.M.'}.freeze

    def initialize(account:)
      @account = account
      raise Unavailable, 'UPS shipping is not enabled' unless account.enabled? && (account.sandbox? || account.production_approved?)

      @origin = account.sandbox? ? 'https://wwwcie.ups.com' : 'https://onlinetools.ups.com'
    end

    def rates(payload)
      with_credentials do
        values = shipment(payload, shipping: false)
        response = request(:post, "/api/rating/#{VERSION}/Shop",
          {'RateRequest' => {'Request' => {'TransactionReference' => {'CustomerContext' => 'Lightek shipping'}},
            'PickupType' => {'Code' => '01'}, 'Shipment' => values}})
        array(response.dig('RateResponse', 'RatedShipment')).filter_map do |row|
          code = row.dig('Service', 'Code')
          cost = cents(row.dig('NegotiatedRateCharges', 'TotalCharge'))
          next unless SERVICES.key?(code) && cost

          {'service_code' => code, 'service_name' => "UPS #{SERVICES.fetch(code)}", 'cost_cents' => cost}
        end
      end
    end

    def ship(payload, reference:)
      with_credentials do
        values = shipment(payload, shipping: true)
        code = payload.fetch('serviceType')
        raise Unavailable, 'Unknown UPS delivery service' unless SERVICES.key?(code)

        values['Service'] = {'Code' => code}
        result = request(:post, "/api/shipments/#{VERSION}/ship",
          {'ShipmentRequest' => {'Request' => {'RequestOption' => 'validate'},
            'Shipment' => values, 'LabelSpecification' => {'LabelImageFormat' => {'Code' => 'GIF'}}}},
          reference: reference).dig('ShipmentResponse', 'ShipmentResults')
        raise Unavailable, 'UPS did not confirm the shipment' unless result.is_a?(Hash)

        documents = array(result['PackageResults']).map do |package|
          package.dig('ShippingLabel', 'GraphicImage').presence || raise(Unavailable, 'UPS label data is missing')
        end
        number = result['ShipmentIdentificationNumber']
        raise Unavailable, 'UPS shipment reference is missing' unless number.to_s.match?(/\A[A-Z0-9]{8,35}\z/)
        cost = cents(result.dig('NegotiatedRateCharges', 'TotalCharge'))
        raise Unavailable, 'UPS did not confirm the account charge' unless cost

        {tracking_number: number, documents: documents, cost_cents: cost}
      end
    end

    def pickup_cost(shipper, day:, ready:, close:)
      with_credentials do
        address = shipper.fetch('address')
        input = {'Request' => {'TransactionReference' => {'CustomerContext' => 'Lightek pickup rate'}},
          'PickupAddress' => {'AddressLine' => address.fetch('streetLines').join(' '), 'City' => address.fetch('city'),
            'StateProvince' => address.fetch('stateOrProvinceCode'), 'PostalCode' => address.fetch('postalCode'),
            'CountryCode' => address.fetch('countryCode'), 'ResidentialIndicator' => address['residential'] ? 'Y' : 'N'},
          'ShipperAccount' => {'AccountNumber' => @credentials.fetch('account_number'), 'AccountCountryCode' => 'US'},
          'AlternateAddressIndicator' => 'Y', 'ServiceDateOption' => '03',
          'PickupDateInfo' => {'PickupDate' => day.strftime('%Y%m%d'), 'ReadyTime' => ready.delete(':'), 'CloseTime' => close.delete(':')}}
        response = request(:post, "/api/shipments/#{VERSION}/pickup/oncall", {'PickupRateRequest' => input}).fetch('PickupRateResponse', {})
        rate = response.fetch('RateResult', {})
        amount = rate['PreTaxTotalIncentedCharge'].presence || rate['PreTaxTotalCharge']
        cost = cents({'CurrencyCode' => rate['CurrencyCode'], 'MonetaryValue' => amount}, allow_zero: true)
        unless response.dig('Response', 'ResponseStatus', 'Code') == '1' && cost
          raise Unavailable, 'UPS did not return a pickup price for this window'
        end

        cost
      end
    end

    def track(number)
      validate_reference!(number)
      with_credentials do
        response = request(:get, "/api/track/v1/details/#{number}")
        event = response.dig('trackResponse', 'shipment', 0, 'package', 0)
        event&.dig('currentStatus', 'description').presence || event&.dig('activity', 0, 'status', 'description')
      end
    end

    def cancel(number)
      validate_reference!(number)
      with_credentials do
        response = request(:delete, "/api/shipments/#{VERSION}/void/cancel/#{number}")
        response.dig('VoidShipmentResponse', 'SummaryResult', 'Status', 'Code') == '1'
      end
    end

    private

    def validate_reference!(number)
      raise Unavailable, 'Invalid UPS shipment reference' unless number.to_s.match?(/\A[A-Z0-9]{8,35}\z/)
    end

    def with_credentials
      @credentials = LightekVault::Service.checkout!(slug: @account.credential_slug, consumer: CONSUMER,
        purpose: 'carrier_shipping', requested_by: 'platform-shipping')
      yield
    ensure
      @credentials&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      @credentials = nil
    end

    def shipment(payload, shipping:)
      account = @credentials.fetch('account_number')
      origin = party(payload.fetch('shipper'))
      recipient = party(payload.fetch('recipients').sole)
      packages = payload.fetch('requestedPackageLineItems').map { |package| package_fields(package, shipping: shipping) }
      data = {'Shipper' => origin.merge('ShipperNumber' => account), 'ShipFrom' => origin, 'ShipTo' => recipient,
        'Package' => packages, 'ShipmentRatingOptions' => {'NegotiatedRatesIndicator' => ''}}
      if shipping
        data['Description'] = 'Merchandise'
        data['PaymentInformation'] = {'ShipmentCharge' => {'Type' => '01', 'BillShipper' => {'AccountNumber' => account}}}
      else
        data['PaymentDetails'] = {'ShipmentCharge' => {'Type' => '01', 'BillShipper' => {'AccountNumber' => account}}}
      end
      data
    end

    def party(party)
      address = party.fetch('address')
      contact = party.fetch('contact')
      fields = {'AddressLine' => address.fetch('streetLines'), 'City' => address.fetch('city'),
        'StateProvinceCode' => address.fetch('stateOrProvinceCode'), 'PostalCode' => address.fetch('postalCode'),
        'CountryCode' => address.fetch('countryCode')}
      fields['ResidentialAddressIndicator'] = '' if address['residential']
      {'Name' => contact.fetch('personName'), 'Address' => fields, 'Phone' => {'Number' => contact.fetch('phoneNumber').gsub(/\D/, '')}}
    end

    def package_fields(item, shipping:)
      dimensions = item.fetch('dimensions')
      packaging = shipping ? 'Packaging' : 'PackagingType'
      {packaging => {'Code' => '02'}, 'Dimensions' => {'UnitOfMeasurement' => {'Code' => 'IN'},
        'Length' => dimensions.fetch('length').to_s, 'Width' => dimensions.fetch('width').to_s, 'Height' => dimensions.fetch('height').to_s},
        'PackageWeight' => {'UnitOfMeasurement' => {'Code' => 'LBS'}, 'Weight' => item.dig('weight', 'value').to_s}}
    end

    def array(value)
      value.is_a?(Hash) ? [value] : Array(value)
    end

    def cents(value, allow_zero: false)
      return unless value.is_a?(Hash) && value['CurrencyCode'] == 'USD' && value['MonetaryValue'].to_s.match?(/\A\d{1,6}(?:\.\d{1,2})?\z/)

      amount = (BigDecimal(value.fetch('MonetaryValue').to_s) * 100).to_i
      amount if amount.positive? || allow_zero
    end

    def token
      key = "lightek-ups-oauth-#{@account.id}-#{@account.updated_at.to_i}-#{@account.sandbox?}"
      Rails.cache.fetch(key, expires_in: 25.minutes) do
        uri = URI("#{@origin}/security/v1/oauth/token")
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(@credentials.fetch('client_id'), @credentials.fetch('client_secret'))
        request.set_form_data(grant_type: 'client_credentials')
        perform(uri, request).fetch('access_token')
      end
    end

    def request(method, path, payload = nil, reference: nil)
      uri = URI("#{@origin}#{path}")
      request = {post: Net::HTTP::Post, get: Net::HTTP::Get, delete: Net::HTTP::Delete}.fetch(method).new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/json'
      request['transId'] = (reference || SecureRandom.hex(16)).delete('-').first(32)
      request['transactionSrc'] = 'Lightek'
      request.body = JSON.generate(payload) if payload
      perform(uri, request)
    end

    def perform(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise Unavailable, 'UPS returned an oversized response' if response.body.to_s.bytesize > 20.megabytes
      raise Unavailable, "UPS could not confirm the request (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, 'UPS did not confirm the operation'
    end
  end
end
