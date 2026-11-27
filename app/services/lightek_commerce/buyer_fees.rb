# frozen_string_literal: true

module LightekCommerce
  # The checkout scope is one unbundled digital product or service,
  # with no shipping, variants, subscription, infrastructure, or upstream shares.
  class BuyerFees
    class Invalid < StandardError; end

    def self.enabled?(site)
      approved_host?(site.host) && site.tenant_type == 'User' &&
        RevenueSharing.snapshot_for(site.tenant).blank?
    end

    def self.approved_host?(host)
      ENV.fetch('LIGHTEK_COMMERCE_BUYER_FEE_HOSTS', '').split(',').map { |entry| entry.strip.downcase }.include?(host.to_s.downcase)
    end

    def self.eligible?(product)
      %w[digital service].include?(product.product_type) && product.billing_interval == 'one_time' &&
        product.price_cents.positive? && product.communications_kind.blank? &&
        product.effective_hosting_package.nil? && product.variants.none?(&:active?)
    end

    def self.quote_for(product)
      quote_amount(product.price_cents)
    end

    def self.quote_amount(merchant_cents)
      tax_code = ENV['LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE'].to_s
      raise Invalid, 'This checkout is waiting for fee tax configuration.' unless tax_code.match?(/\Atxcd_\d{8}\z/)

      BuyerPrice.quote(merchant_cents: merchant_cents).stringify_keys.merge('tax_code' => tax_code)
    rescue ArgumentError
      raise Invalid, 'This checkout is waiting for valid fee settings.'
    end

    def self.snapshot_for(site:, products:, requested:, token:, shipping_quote:)
      active = enabled?(site) && products.any? { |product| eligible?(product) }
      return {} unless active || token.present?

      product = products.first
      unless active && products.one? && requested == {product.id.to_s => 1} && shipping_quote.nil?
        raise Invalid, 'This checkout is for one eligible item. Review your cart and price.'
      end
      quote = quote_for(product)
      payload = verifier.verified(token.to_s)
      unless payload.is_a?(Array) && payload.first(3) == [site.id, product.id, quote]
        raise Invalid, 'The checkout price changed or expired. Review the buyer total before continuing.'
      end

      quote
    end

    def self.sign(site, product, quote)
      verifier.generate([site.id, product.id, quote, SecureRandom.hex(12)], expires_in: 15.minutes)
    end

    def self.verifier
      Rails.application.message_verifier('commerce-buyer-fee-price')
    end
    private_class_method :verifier
  end
end
