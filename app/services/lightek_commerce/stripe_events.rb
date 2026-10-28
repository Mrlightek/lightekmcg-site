# frozen_string_literal: true
module LightekCommerce
  class StripeEvents
    class Rejected < StandardError; end

    def self.process!(event)
      return unless %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired].include?(event.type)
      session = event.data.object
      order_id = session.metadata.to_h["lightek_commerce_order_id"].to_s
      order = Order.find_by(id: order_id)
      raise Rejected, "Unknown commerce order" unless order
      raise Rejected, "Mismatched site" unless session.metadata.to_h["lightek_site_id"].to_s == order.site_id.to_s
      raise Rejected, "Mismatched checkout" unless session.id == order.payment_reference
      raise Rejected, "Mismatched currency" unless session.currency.to_s.downcase == order.currency

      if event.type == "checkout.session.expired"
        # Never release inventory for a paid order. Reconciliation also checks
        # Stripe directly before canceling overdue reservations.
        OrderPlacement.cancel!(order) if order.status == "pending_payment"
        return order
      end
      return order unless session.mode == "payment" && session.payment_status == "paid"
      order.with_lock do
        return order if %w[paid fulfilled refunded].include?(order.status)
        raise Rejected, "Order is no longer payable" unless order.status == "pending_payment"
        subtotal = session.amount_subtotal.to_i
        tax = session.total_details.amount_tax.to_i
        shipping = session.total_details.amount_shipping.to_i
        total = session.amount_total.to_i
        raise Rejected, "Mismatched line items" unless subtotal == order.subtotal_cents
        raise Rejected, "Mismatched totals" unless subtotal + tax + shipping == total && total >= subtotal
        order.update!(status: "paid", paid_at: Time.current, tax_cents: tax, shipping_cents: shipping, total_cents: total)
        OrderConfirmationJob.perform_later(order.id)
      end
      order
    end
  end
end
