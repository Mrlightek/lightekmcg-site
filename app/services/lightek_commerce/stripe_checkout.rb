# frozen_string_literal: true
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    def self.start!(order:, success_url:, cancel_url:)
      LightekAgency::Demos.ensure_live_site!(order.site, error: Unavailable) if defined?(LightekAgency::Demos)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment"
      return NetworkCheckout.start!(order: order, success_url: success_url, cancel_url: cancel_url) if NetworkCheckout.connected?(order)
      return resume!(order: order) if order.payment_reference.present?
      begin
        InstanceReadiness.check!(order: order)
      rescue InstanceReadiness::Unavailable => e
        raise Unavailable, e.message
      end
      key = DymondBank::StripeCredentials.secret_key
      raise Unavailable, "Stripe is not configured" if key.blank?
      Stripe.api_key = key
      if order.shipping_quote
        stripe_test = key.match?(/\A(?:sk|rk)_test_/)
        raise Unavailable, "FedEx and Stripe must use the same test or production mode" unless order.shipping_quote.sandbox? == stripe_test
      end
      interval = order.items.first.purchase_snapshot.to_h.fetch("billing_interval", "one_time")
      recurring = interval != "one_time"
      raise Unavailable, "Subscriptions require one item with quantity one" if recurring && (order.items.size != 1 || order.items.first.quantity != 1)
      line_items = order.items.map { |item|
        {price_data: {currency: order.currency, unit_amount: item.unit_price_cents,
          product_data: {name: item.name}, **(recurring ? {recurring: {interval: interval}} : {})}, quantity: item.quantity}
      }
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
          {idempotency_key: PaymentIdentity.key(order, "shipping-customer")})
        customer = {customer: record.id}
      end
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
        success_url: success_url,
        cancel_url: cancel_url,
        expires_at: 30.minutes.from_now.to_i
      }, {idempotency_key: PaymentIdentity.key(order, 'checkout')})
      order.update!(payment_provider: "stripe", payment_reference: session.id)
      session
    rescue ::Stripe::StripeError => e
      raise Unavailable, e.message
    end

    def self.resume!(order:)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment" && order.payment_provider == "stripe"
      Stripe.api_key = DymondBank::StripeCredentials.secret_key
      session = Stripe::Checkout::Session.retrieve(order.payment_reference)
      metadata = session.metadata.to_h.stringify_keys
      raise Unavailable, "Checkout does not match this order" unless session.id == order.payment_reference &&
        metadata["lightek_commerce_order_id"].to_s == order.id.to_s && metadata["lightek_site_id"].to_s == order.site_id.to_s
      raise Unavailable, "Checkout has completed or expired; wait for payment confirmation" unless session.status == "open" && session.url.present?
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
