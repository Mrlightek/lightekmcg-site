module LightekCommerce
  class NetworkGateway
    def self.return_url!(peer, value)
      uri = URI.parse(value)
      raise ArgumentError, "Invalid commerce return address" unless uri.is_a?(URI::HTTPS) && uri.host == peer.site.host && uri.port == 443 && !uri.userinfo && !uri.fragment && %w[/commerce/shop /dashboard/commerce /dashboard/commerce/payouts].include?(uri.path)
      uri.to_s
    end
    def self.reserve!(peer:, attributes:)
      attrs = attributes.deep_stringify_keys
      key = attrs.fetch("source_key")
      raise ArgumentError, "Invalid checkout identity" unless key.match?(/\A[a-f0-9]{64}\z/)
      return_url = return_url!(peer, attrs.fetch("return_url"))
      stable = attrs.slice("customer_email", "items", "shipping_quote_key", "shipping_price_cents")
      # Rails parameters preserve this value as a number for JSON requests.
      # Normalize equivalent numeric input before enforcing replay equality.
      if attrs.key?('buyer_price_cents')
        stable['buyer_price_cents'] = Integer(attrs['buyer_price_cents'].to_s, 10)
      end
      peer.with_lock do
        sale = NetworkSale.find_by(peer: peer, source_key: key)
        if sale
          raise ArgumentError, "Existing checkout does not match this purchase" unless sale.source_snapshot == stable
          return sale
        end
        merchant, site = NetworkAccounts.resolve!(peer: peer, chain: attrs.fetch("merchant_chain"), store_name: attrs.fetch("store_name"))
        rows = attrs.fetch("items")
        raise ArgumentError, "Use between 1 and 50 line items" unless rows.is_a?(Array) && rows.size.between?(1, 50)
        rows.each do |row|
          raise ArgumentError, "Invalid line item" unless row.fetch("quantity").to_s.match?(/\A[1-9]\d*\z/) && row["quantity"].to_i <= 100 &&
            row.fetch("unit_price_cents").to_s.match?(/\A\d+\z/) && row.fetch("product_type").in?(%w[physical digital service]) && row.fetch("billing_interval").in?(%w[one_time month year])
        end
        recurring = rows.any? { |row| row["billing_interval"] != "one_time" }
        raise ArgumentError, "Subscriptions must be purchased separately" if recurring && (rows.size != 1 || rows.first["quantity"].to_i != 1 || rows.first["product_type"] != "service")
        subtotal = rows.sum { |row| row["quantity"].to_i * row["unit_price_cents"].to_i }
        raise ArgumentError, "Checkout total is outside the supported range" unless subtotal.between?(0, 2_000_000_000)
        source_quote = nil
        quote = nil
        shipping = 0
        if attrs["shipping_quote_key"].present?
          source_quote = LightekShipping::Quote.where(site: peer.site).find_by!(public_key: attrs["shipping_quote_key"])
          raise ArgumentError, "Shipping quote has expired" if source_quote.expires_at <= Time.current
          shipping = Integer(attrs.fetch("shipping_price_cents"))
          raise ArgumentError, "Shipping price is below the platform rate" if shipping < source_quote.platform_price_cents || shipping > 10_000_000
          quote = source_quote.dup
          quote.assign_attributes(site: site, public_key: SecureRandom.uuid, customer_price_cents: shipping, purchase_order_id: nil)
          quote.save!
        end
        fee = buyer_fee_snapshot(peer: peer, merchant: merchant, subtotal: subtotal, buyer_price_cents: stable['buyer_price_cents'])
        order = Order.new(site: site, customer_email: attrs.fetch("customer_email"), subtotal_cents: subtotal,
          shipping_cents: shipping, stock_reserved: false, shipping_quote: quote)
        order.buyer_fee_snapshot = fee if fee.present?
        order.total_cents = subtotal + shipping + order.buyer_fee_cents
        order.save!
        rows.each do |row|
          product = Product.create!(site: site, slug: "network-#{SecureRandom.hex(12)}", name: row.fetch("name").to_s.first(160),
            price_cents: row["unit_price_cents"].to_i, product_type: row["product_type"], billing_interval: row["billing_interval"],
            published: false, inventory_quantity: 0, track_inventory: false)
          order.items.create!(product: product, name: product.name, quantity: row["quantity"].to_i, unit_price_cents: product.price_cents,
            line_total_cents: product.price_cents * row["quantity"].to_i,
            purchase_snapshot: {"product_type" => product.product_type, "billing_interval" => product.billing_interval, "track_inventory" => false})
        end
        MerchantPayouts.fee_quote(order, gross_cents: (order.total_cents * 125 + 99) / 100)
        sale = NetworkSale.create!(peer: peer, order: order, source_key: key, source_snapshot: stable,
          source_shipping_quote: source_quote, return_url: return_url)
        ReservationExpiryJob.set(wait: 30.minutes).perform_later(order.id)
        sale
      end
    end
    def self.buyer_fee_snapshot(peer:, merchant:, subtotal:, buyer_price_cents:)
      return {} unless buyer_price_cents

      unless BuyerFees.approved_host?(peer.site.host) && subtotal.positive? && RevenueSharing.snapshot_for(merchant).blank?
        raise BuyerFees::Invalid, 'This store or order does not support buyer-paid fees.'
      end

      quote = BuyerFees.quote_amount(subtotal)
      unless quote.fetch('buyer_cents') == buyer_price_cents
        raise BuyerFees::Invalid, 'The checkout price changed. Review your cart before continuing.'
      end

      quote
    end
    private_class_method :buyer_fee_snapshot

    def self.checkout!(sale, embedded: false)
      order = sale.order
      result = {key: sale.public_key, buyer_fee_cents: order.buyer_fee_cents}
      return result.merge(url: sale.return_url) if order.paid_at?

      checkout = StripeCheckout.start!(order: order, success_url: sale.return_url, cancel_url: sale.return_url,
        embedded: embedded && StripeCheckout.embedded_for?(order))
      if checkout.url.present?
        result.merge(url: checkout.url)
      elsif checkout.ui_mode == StripeCheckout::EMBEDDED_MODE && checkout.client_secret.present?
        result.merge(embedded: true)
      else
        raise StripeCheckout::Unavailable, 'The network payment session could not be verified.'
      end
    end

    def self.embedded_session!(sale)
      checkout = StripeCheckout.resume!(order: sale.order, embedded: true)
      {key: sale.public_key, client_secret: checkout.client_secret, publishable_key: StripeCheckout.embedded_publishable_key}
    end
    def self.serialize_order(order)
      {ledger_site_id: order.site_id, ledger_order_id: order.id, status: order.status, subtotal_cents: order.subtotal_cents, shipping_cents: order.shipping_cents, tax_cents: order.tax_cents,
        total_cents: order.total_cents, buyer_fee_cents: order.buyer_fee_cents, refunded_cents: order.refunded_cents, paid_at: order.paid_at&.iso8601,
        fulfilled_at: order.fulfilled_at&.iso8601, fulfillment_reference: order.fulfillment_reference,
        merchant_transfer_ref: order.merchant_transfer_ref, merchant_transfer_amount_cents: order.merchant_transfer_amount_cents}
    end
    def self.receipt(sale)
      order = sale.order.reload
      result = serialize_order(order)
      subscription = order.commerce_subscription
      if subscription
        result[:subscription] = subscription.attributes.slice("processor_reference", "customer_reference", "status", "billing_interval", "amount_cents", "currency", "current_period_end", "cancel_at_period_end")
        result[:invoices] = subscription.billing_invoices.includes(:settlement_order).order(:id).map do |invoice|
          {initial: invoice.settlement_order_id == order.id, reference: invoice.processor_reference, amount_paid_cents: invoice.amount_paid_cents, paid_at: invoice.paid_at.iso8601,
            order: invoice.settlement_order && serialize_order(invoice.settlement_order)}
        end
      end
      result
    end
    def self.order_for(sale, invoice_reference: nil)
      return sale.order if invoice_reference.blank?
      sale.order.commerce_subscription.billing_invoices.find_by!(processor_reference: invoice_reference).settlement_order || raise(ActiveRecord::RecordNotFound)
    end
  end
end
