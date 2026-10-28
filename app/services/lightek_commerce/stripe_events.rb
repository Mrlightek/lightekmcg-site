# frozen_string_literal: true
module LightekCommerce
  class StripeEvents
    class Rejected < StandardError; end
    def self.process!(event)
      return unless event.type == "checkout.session.completed"
      session = event.data.object
      return unless session.mode == "payment" && session.payment_status == "paid"
      order_id = session.metadata["lightek_commerce_order_id"].to_s
      Order.transaction do
        order = Order.lock.find_by(id: order_id)
        raise Rejected, "Unknown commerce order" unless order
        raise Rejected, "Mismatched site" unless session.metadata["lightek_site_id"].to_s == order.site_id.to_s
        raise Rejected, "Mismatched checkout" unless session.id == order.payment_reference
        raise Rejected, "Mismatched currency" unless session.currency.to_s.downcase == order.currency
        expected = session.amount_total.to_i
        raise Rejected, "Invalid total" unless expected >= order.subtotal_cents && session.amount_subtotal.to_i == order.subtotal_cents
        return order if order.status == "paid"
        raise Rejected, "Order is not pending payment" unless order.status == "pending_payment"
        tax = session.total_details.amount_tax.to_i
        shipping = session.total_details.amount_shipping.to_i
        raise Rejected, "Mismatched totals" unless order.subtotal_cents + tax + shipping == expected
        order.update!(status: "paid", paid_at: Time.current, tax_cents: tax, shipping_cents: shipping,
          total_cents: expected)
        order
      end
    end
  end
end
