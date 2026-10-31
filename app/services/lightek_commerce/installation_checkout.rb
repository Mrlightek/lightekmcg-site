# frozen_string_literal: true
module LightekCommerce
  class InstallationCheckout
    class Invalid < StandardError; end

    # Persist the order before contacting Stripe. Repeated submissions of the
    # same form reuse its order and Stripe's existing order-bound idempotency key.
    def self.reserve!(actor:, product:, checkout_key:)
      checkout_key = checkout_key.to_s.downcase
      raise Invalid, "Invalid checkout key" unless checkout_key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
      raise Invalid, "Installation product required" unless product.published? && product.product_type == "lightek_instance"
      actor.with_lock do
        order = Order.find_by(customer_email: actor.email_address, client_checkout_key: checkout_key)
        if order
          raise Invalid, "Checkout product mismatch" unless order.items.one? && order.items.first.product_id == product.id && order.items.first.quantity == 1
          return order
        end
        order = OrderPlacement.call(site: product.site, customer_email: actor.email_address, quantities: {product.id.to_s => 1})
        order.update!(client_checkout_key: checkout_key)
        order
      end
    end
  end
end
