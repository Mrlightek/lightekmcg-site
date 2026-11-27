# frozen_string_literal: true

module LightekCommerce
  # A tender-neutral pricing preview. The published buyer price can include
  # the Lightek network fee and estimated processing on the entire buyer amount.
  class BuyerPrice
    def self.quote(merchant_cents:, processor_bps: ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS', '300'),
      processor_fixed_cents: ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS', '30'),
      network_bps: ENV.fetch('LIGHTEK_COMMERCE_BUYER_NETWORK_FEE_BPS', '0'),
      network_fixed_cents: ENV.fetch('LIGHTEK_COMMERCE_BUYER_NETWORK_FIXED_CENTS', '0'))
      merchant_cents = Integer(merchant_cents)
      processor_bps = Integer(processor_bps)
      processor_fixed_cents = Integer(processor_fixed_cents)
      network_bps = Integer(network_bps)
      network_fixed_cents = Integer(network_fixed_cents)
      unless merchant_cents.positive? && processor_bps.in?(0..2500) && network_bps.in?(0..2500) &&
          processor_fixed_cents.in?(0..2000) && network_fixed_cents.in?(0..2000)
        raise ArgumentError, 'The price or fee settings are outside the supported range.'
      end

      network_cents = network_fixed_cents + (merchant_cents * network_bps + 9999).div(10_000)
      base = merchant_cents + network_cents + processor_fixed_cents
      divisor = 10_000 - processor_bps
      buyer_cents = (base * 10_000 + divisor - 1).div(divisor)
      {merchant_cents: merchant_cents, network_cents: network_cents,
       processor_reserve_cents: buyer_cents - merchant_cents - network_cents, buyer_cents: buyer_cents}
    end
  end
end
