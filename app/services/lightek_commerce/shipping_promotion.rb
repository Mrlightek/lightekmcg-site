# frozen_string_literal: true

module LightekCommerce
  class ShippingPromotion
    class Invalid < StandardError; end

    CONFIG_KEY = 'commerce_free_shipping'
    MAX_THRESHOLD_CENTS = 100_000_000

    def self.settings(site)
      site.manifest.to_h.fetch(CONFIG_KEY, {}).to_h
    end

    def self.save!(site, attributes)
      minimum = Integer(attributes['minimum_cents'].to_s, 10)
      maximum = Integer(attributes['maximum_rate_cents'].to_s, 10)
      unless minimum.between?(0, MAX_THRESHOLD_CENTS) && maximum.between?(1, 10_000_000)
        raise Invalid, 'Enter a valid merchandise minimum and a positive maximum shipping rate in cents.'
      end

      code = Discount.normalize(attributes['code'])
      if code && !code.match?(/\A[A-Z0-9_-]{1,40}\z/)
        raise Invalid, 'Use up to 40 letters, numbers, hyphens, or underscores for the shipping code.'
      end
      value = {'code' => code, 'enabled' => attributes['enabled'] == '1', 'minimum_cents' => minimum, 'maximum_rate_cents' => maximum}
      site.with_lock { site.update!(manifest: site.manifest.to_h.merge(CONFIG_KEY => value)) }
    rescue ArgumentError
      raise Invalid, 'Enter a valid merchandise minimum and maximum shipping rate in cents.'
    end

    def self.valid_code?(site, code)
      config = settings(site)
      config['enabled'] == true && config['code'].present? && Discount.normalize(code) == config['code']
    end

    def self.savings(site:, quote:, subtotal:, buyer_fee:, merchandise_discount:, code: nil)
      config = settings(site)
      return 0 unless config['enabled'] == true && quote&.site_id == site.id
      return 0 if config['code'].present? && Discount.normalize(code) != config['code']
      return 0 unless subtotal >= config.fetch('minimum_cents') && quote.customer_price_cents <= config.fetch('maximum_rate_cents')
      return 0 if merchandise_discount&.entries&.any? { |rule, _| !rule.combinable? }

      price = quote.customer_price_cents
      estimate = Order.new(site: site, shipping_quote: quote, subtotal_cents: subtotal,
        buyer_fee_snapshot: buyer_fee, shipping_discount_cents: price, revenue_share_snapshot: RevenueSharing.snapshot_for(site.tenant))
      gross = subtotal + estimate.buyer_fee_cents
      MerchantPayouts.fee_quote(estimate, gross_cents: (gross * 125 + 99) / 100)
      price
    rescue MerchantPayouts::Invalid, RevenueSharing::Invalid
      0
    end

    def self.signed_review(site, quote, discount)
      verifier.generate(identity(site, quote, discount), expires_at: quote.expires_at)
    end

    def self.valid_review?(site, quote, discount, token)
      (discount.zero? && token.blank?) || verifier.verified(token.to_s) == identity(site, quote, discount)
    end

    def self.identity(site, quote, discount)
      [site.id, quote.id, quote.cart_fingerprint, quote.customer_price_cents, discount]
    end
    private_class_method :identity

    def self.verifier
      Rails.application.message_verifier('commerce-shipping-promotion-v1')
    end
    private_class_method :verifier
  end
end
