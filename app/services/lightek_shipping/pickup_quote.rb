# frozen_string_literal: true

module LightekShipping
  class PickupQuote
    def self.rate!(quote:, attributes:)
      raise ArgumentError, 'Pickup pricing is currently available for UPS shipments' unless quote.provider == 'ups'

      values = attributes.to_h.stringify_keys
      day = Date.iso8601(values.fetch('date').to_s)
      ready = values['ready'].to_s
      close = values['close'].to_s
      clock = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/
      unless day.between?(Date.current, Date.current + 30) && ready.match?(clock) && close.match?(clock) && ready < close
        raise ArgumentError, 'Choose a pickup date within 30 days and a closing time after the ready time'
      end

      if quote.broker_reference.present?
        remote = LightekReservations::Federation::Client.new(quote.site).request("shipping/quotes/#{quote.broker_reference}/pickup-rate",
          method: :post, body: {pickup: values.slice('date', 'ready', 'close')})
        return Integer(remote.fetch('price_cents').to_s, 10)
      end

      account = Account.find_by!(provider: 'ups', enabled: true)
      raise ArgumentError, 'Shipping environment changed; review the original quote' unless account.sandbox? == quote.sandbox?

      cost = Ups.new(account: account).pickup_cost(quote.shipment_payload.fetch('shipper'), day: day, ready: ready, close: close)
      cost + Account::UPS_MARKUP_CENTS
    rescue Date::Error, KeyError
      raise ArgumentError, 'Enter a valid pickup date, ready time, and closing time'
    end
  end
end
