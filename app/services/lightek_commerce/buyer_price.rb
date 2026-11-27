# frozen_string_literal: true

module LightekCommerce
  # Pretax, tender-neutral pricing preview. Gross up processing before
  # rounding, then recalculate processing on the rounded buyer amount.
  class BuyerPrice
    MINIMUM_NETWORK_FEE_CENTS = 200
    BUYER_PRICE_INCREMENT_CENTS = 200

    def self.quote(merchant_cents:, processor_bps: ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS', '300'),
      processor_fixed_cents: ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS', '30'))
      merchant_cents = Integer(merchant_cents)
      processor_bps = Integer(processor_bps)
      processor_fixed_cents = Integer(processor_fixed_cents)
      unless merchant_cents.positive? && processor_bps.in?(0..2500) && processor_fixed_cents.in?(0..2000)
        raise ArgumentError, 'The price or fee settings are outside the supported range.'
      end

      base_cents = merchant_cents + MINIMUM_NETWORK_FEE_CENTS + processor_fixed_cents
      divisor = 10_000 - processor_bps
      minimum_buyer_cents = (base_cents * 10_000 + divisor - 1).div(divisor)
      buyer_cents = (minimum_buyer_cents + BUYER_PRICE_INCREMENT_CENTS - 1)
        .div(BUYER_PRICE_INCREMENT_CENTS) * BUYER_PRICE_INCREMENT_CENTS
      processor_cents = (buyer_cents * processor_bps + 9999).div(10_000) + processor_fixed_cents
      network_cents = buyer_cents - merchant_cents - processor_cents

      {merchant_cents: merchant_cents, minimum_network_cents: MINIMUM_NETWORK_FEE_CENTS,
       rounding_network_cents: network_cents - MINIMUM_NETWORK_FEE_CENTS,
       network_cents: network_cents, processor_reserve_cents: processor_cents, buyer_cents: buyer_cents}
    end
  end
end
