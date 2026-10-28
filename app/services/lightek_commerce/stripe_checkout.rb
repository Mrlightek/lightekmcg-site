# frozen_string_literal: true
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    def self.start!(order:, success_url:, cancel_url:)
      raise Unavailable, "Order is not payable" unless order.status == "pending_payment"
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

    def self.shipping_parameters(order)
      return {} if order.items.all? { |item| item.product.product_type == "digital" }
      {shipping_address_collection: {allowed_countries: ["US"]}, shipping_options: shipping_options}
    end

    def self.shipping_options
      ids = ENV.fetch("LIGHTEK_COMMERCE_STRIPE_SHIPPING_RATE_IDS", "").split(",").map(&:strip).reject(&:blank?)
      raise Unavailable, "Configure shipping rates before accepting orders" if ids.empty?
      ids.map { |id| {shipping_rate: id} }
    end

  end
end
