# frozen_string_literal: true
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    EMBEDDED_MODE = 'embedded_page'

    def self.embedded_for?(order, network: false)
      return false if ENV.fetch('LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT', 'true') == 'false'

      return network if NetworkCheckout.connected?(order)

      embedded_publishable_key.present?
    rescue Unavailable
      false
    end

    def self.embedded_publishable_key
      LightekPayments::PayoutAccounts.publishable_key(LightekPayments::PayoutAccounts.options)
    rescue LightekPayments::PayoutAccounts::Unavailable
      raise Unavailable, 'Embedded checkout needs a matching platform publishable key.'
    end

    def self.start!(order:, success_url:, cancel_url:, embedded: false)
      order.with_lock { start_locked!(order: order, success_url: success_url, cancel_url: cancel_url, embedded: embedded) }
    end

    def self.start_locked!(order:, success_url:, cancel_url:, embedded:)
      LightekAgency::Demos.ensure_live_site!(order.site, error: Unavailable) if defined?(LightekAgency::Demos)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment"
      if order.items.any? { |item| item.product.full_communications_package? } &&
          !(defined?(LightekCommunications::FullPackage) && LightekCommunications::FullPackage.exists?(order_id: order.id))
        raise Unavailable, "This package must complete setup before payment."
      end
      if NetworkCheckout.connected?(order)
        if order.payment_reference.present? && order.payment_provider != 'network'
          return resume!(order: order, embedded: :either)
        end

        return NetworkCheckout.start!(order: order, embedded: embedded)
      end
      return resume!(order: order, embedded: :either) if order.payment_reference.present?

      embedded_publishable_key if embedded
      begin
        InstanceReadiness.check!(order: order)
      rescue InstanceReadiness::Unavailable => e
        raise Unavailable, e.message
      end
      key = DymondBank::StripeCredentials.secret_key
      raise Unavailable, "Payments are not configured" if key.blank?
      options = {api_key: key}
      if order.shipping_quote
        stripe_test = key.match?(/\A(?:sk|rk)_test_/)
        raise Unavailable, "Shipping and payments must use the same test or production mode" unless order.shipping_quote.sandbox? == stripe_test
      end
      interval = order.items.first.purchase_snapshot.to_h.fetch("billing_interval", "one_time")
      recurring = interval != "one_time"
      raise Unavailable, "Subscriptions require one item with quantity one" if recurring && (order.items.size != 1 || order.items.first.quantity != 1)
      line_items = if order.discount_amount.positive?
        Discounts.processor_items(order)
      else
        order.items.map do |item|
          {price_data: {currency: order.currency, unit_amount: item.unit_price_cents,
            product_data: {name: item.name}, **(recurring ? {recurring: {interval: interval}} : {})}, quantity: item.quantity}
        end
      end
      if order.buyer_fee_cents.positive?
        line_items << {price_data: {currency: order.currency, unit_amount: order.buyer_fee_cents,
          product_data: {name: 'Lightek checkout fee', tax_code: order.buyer_fee_breakdown.fetch('tax_code')},
          tax_behavior: 'exclusive', **(recurring ? {recurring: {interval: interval}} : {})}, quantity: 1}
      end
      customer = {customer_email: order.customer_email}
      if order.shipping_quote && order.purpose != "shipping_label"
        raise Unavailable, "Shipping quote has expired" if order.shipping_quote.expires_at <= Time.current
        line_items << {price_data: {currency: order.currency, unit_amount: order.shipping_quote.customer_price_cents,
          product_data: {name: "#{order.shipping_quote.service_name} shipping", tax_code: "txcd_92010001"}}, quantity: 1}
        party = order.shipping_quote.shipment_payload.fetch("recipients").sole
        address = party.fetch("address")
        shipping = {name: party.fetch("contact").fetch("personName"), phone: party.fetch("contact").fetch("phoneNumber"),
          address: {line1: address.fetch("streetLines").first, city: address.fetch("city"), state: address.fetch("stateOrProvinceCode"), postal_code: address.fetch("postalCode"), country: address.fetch("countryCode")}}
        # A saved, order-specific shipping address keeps the accepted rate and
        # Stripe Tax destination aligned without a second editable address form.
        record = Stripe::Customer.create({email: order.customer_email, shipping: shipping, metadata: PaymentIdentity.metadata(order)},
          options.merge(idempotency_key: PaymentIdentity.key(order, "shipping-customer")))
        customer = {customer: record.id}
      end
      raise Unavailable, "Split this cart into smaller orders." if line_items.size > 100
      session = Stripe::Checkout::Session.create({
        mode: recurring ? "subscription" : "payment",
        **(recurring ? {subscription_data: {metadata: PaymentIdentity.metadata(order)}} : {}),
        **customer,
        client_reference_id: order.id.to_s,
        metadata: PaymentIdentity.metadata(order),
        line_items: line_items,
        automatic_tax: {enabled: true},
        **shipping_parameters(order),
        billing_address_collection: "required",
        **(embedded ? {ui_mode: EMBEDDED_MODE, return_url: success_url, redirect_on_completion: 'if_required'} :
          {success_url: success_url, cancel_url: cancel_url}),
        expires_at: 30.minutes.from_now.to_i
      }, options.merge(idempotency_key: PaymentIdentity.key(order, 'checkout')))
      order.update!(payment_provider: "stripe", payment_reference: session.id)
      session
    rescue ::Stripe::StripeError => e
      raise Unavailable, "Payment checkout is temporarily unavailable. Please retry."
    end
    private_class_method :start_locked!

    def self.resume!(order:, embedded: false)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment" && order.payment_provider == "stripe"
      session = Stripe::Checkout::Session.retrieve(order.payment_reference, api_key: DymondBank::StripeCredentials.secret_key)
      metadata = session.metadata.to_h.stringify_keys
      raise Unavailable, "Checkout does not match this order" unless session.id == order.payment_reference &&
        metadata["lightek_commerce_order_id"].to_s == order.id.to_s && metadata["lightek_site_id"].to_s == order.site_id.to_s
      available = embedded != true && session.url.present?
      if !available && embedded
        available = session.ui_mode == EMBEDDED_MODE && session.client_secret.present? &&
          metadata['lightek_host_key'] == order.payment_namespace && order.payment_namespace.present?
      end
      raise Unavailable, "Checkout has completed or expired; wait for payment confirmation" unless session.status == "open" && available
      session
    rescue ::Stripe::StripeError
      raise Unavailable, "Existing checkout is temporarily unavailable"
    end

    def self.shipping_parameters(order)
      return {} if order.shipping_quote && order.purpose != "shipping_label"
      return {} if order.items.all? { |item| ["digital", "service", "lightek_instance"].include?(item.product.product_type) }
      {shipping_address_collection: {allowed_countries: ["US"]}, shipping_options: shipping_options}
    end

    def self.shipping_options
      ids = ENV.fetch("LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS", "").split(",").map(&:strip).reject(&:blank?)
      raise Unavailable, "Configure shipping rates before accepting orders" if ids.empty?
      ids.map { |id| {shipping_rate: id} }
    end

  end
end
