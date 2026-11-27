# frozen_string_literal: true

module LightekCommerce
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
      %w[physical digital service].include?(product.product_type) &&
        product.communications_kind.blank? && product.effective_hosting_package.nil?
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

    def self.cart_price(products:, requested:, lock: false, price_only: false)
      return if products.empty? || products.none? { |product| eligible?(product) }
      unless products.all? { |product| eligible?(product) }
        raise Invalid, 'Check out hosting and communications products separately.'
      end

      catalog = products.index_by { |product| product.id.to_s }
      lines = requested.sort.map do |key, quantity|
        product_id, variant_id = key.split(':')
        product = catalog[product_id]
        raise Invalid, 'Review unavailable items in your cart.' unless product

        variants = product.variants.where(active: true)
        variants = variants.lock if lock
        variant = variants.find_by(id: variant_id) if variant_id
        if variant_id ? variant.nil? : variants.exists?
          raise Invalid, 'Review the product options in your cart.'
        end

        [key, quantity.to_i, variant&.price_cents || product.price_cents, product.billing_interval]
      end
      recurring = lines.any? { |line| line.last != 'one_time' }
      if recurring && (lines.size != 1 || lines.first[1] != 1 || lines.first[0].include?(':'))
        raise Invalid, 'Purchase each subscription separately, quantity one.'
      end

      subtotal = lines.sum { |_, quantity, unit_price, _| quantity * unit_price }
      return [lines, subtotal] if price_only
      return if subtotal.zero?

      [lines, quote_amount(subtotal)]
    end

    def self.snapshot_for(site:, products:, requested:, token:)
      price = cart_price(products: products, requested: requested, lock: true) if enabled?(site)
      return {} unless price || token.present?

      payload = verifier.verified(token.to_s)
      if price && payload.is_a?(Array)
        lines, quote = price
        return quote if payload.first(3) == [site.id, lines, quote]
        # Accept a price reviewed just before upgrading from the single-item checkout.
        key, quantity, _, interval = lines.first
        if lines.one? && quantity == 1 && !key.include?(':') && interval == 'one_time' &&
            payload.first(3) == [site.id, key.to_i, quote]
          return quote
        end
      end

      raise Invalid, 'The checkout price changed or expired. Review the buyer total before continuing.'
    end

    def self.sign(site, selection, quote)
      selection = selection.id if selection.respond_to?(:id)
      verifier.generate([site.id, selection, quote, SecureRandom.hex(12)], expires_in: 15.minutes)
    end

    def self.verifier
      Rails.application.message_verifier('commerce-buyer-fee-price')
    end
    private_class_method :verifier
  end
end
