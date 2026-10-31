# frozen_string_literal: true
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    def self.start!(order:, success_url:, cancel_url:)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment"
      return resume!(order: order) if order.payment_reference.present?
      begin
        InstanceReadiness.check!(order: order)
      rescue InstanceReadiness::Unavailable => e
        raise Unavailable, e.message
      end
      key = DymondBank::StripeCredentials.secret_key
      raise Unavailable, "Stripe is not configured" if key.blank?
      Stripe.api_key = key
      session = Stripe::Checkout::Session.create({
        mode: "payment",
        customer_email: order.customer_email,
        client_reference_id: order.id.to_s,
        metadata: {lightek_commerce_order_id: order.id.to_s, lightek_site_id: order.site_id.to_s},
        line_items: order.items.map { |item|
          {price_data: {currency: order.currency, unit_amount: item.unit_price_cents,
            product_data: {name: item.name}}, quantity: item.quantity}
        },
        automatic_tax: {enabled: true},
        **shipping_parameters(order),
        billing_address_collection: "required",
        success_url: success_url,
        cancel_url: cancel_url,
        expires_at: 30.minutes.from_now.to_i
      }, {idempotency_key: "lightek-commerce-order-#{order.id}-checkout"})
      order.update!(payment_provider: "stripe", payment_reference: session.id)
      session
    rescue ::Stripe::StripeError => e
      raise Unavailable, e.message
    end

    def self.resume!(order:)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment" && order.payment_provider == "stripe"
      Stripe.api_key = DymondBank::StripeCredentials.secret_key
      session = Stripe::Checkout::Session.retrieve(order.payment_reference)
      metadata = session.metadata.to_h
      raise Unavailable, "Checkout does not match this order" unless session.id == order.payment_reference &&
        metadata["lightek_commerce_order_id"].to_s == order.id.to_s && metadata["lightek_site_id"].to_s == order.site_id.to_s
      raise Unavailable, "Checkout has completed or expired; wait for payment confirmation" unless session.status == "open" && session.url.present?
      session
    rescue ::Stripe::StripeError
      raise Unavailable, "Existing checkout is temporarily unavailable"
    end

    def self.shipping_parameters(order)
      return {} if order.items.all? { |item| ["digital", "lightek_instance"].include?(item.product.product_type) }
      {shipping_address_collection: {allowed_countries: ["US"]}, shipping_options: shipping_options}
    end

    def self.shipping_options
      ids = ENV.fetch("LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS", "").split(",").map(&:strip).reject(&:blank?)
      raise Unavailable, "Configure shipping rates before accepting orders" if ids.empty?
      ids.map { |id| {shipping_rate: id} }
    end

  end
end
