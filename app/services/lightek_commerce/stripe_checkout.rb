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
  end
end
