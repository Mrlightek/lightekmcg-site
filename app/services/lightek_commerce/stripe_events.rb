# frozen_string_literal: true
module LightekCommerce
  class StripeEvents
    class Rejected < StandardError; end

    def self.process!(event)
      if %w[charge.refund.updated refund.updated].include?(event.type)
        refund = event.data.object
        return RefundSettlement.call(processor_ref: refund.id, status: refund.status)
      end
      return unless %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired].include?(event.type)
      session = event.data.object
      order_id = session.metadata.to_h["lightek_commerce_order_id"].to_s
      order = Order.find_by(id: order_id)
      raise Rejected, "Unknown commerce order" unless order
      raise Rejected, "Mismatched site" unless session.metadata.to_h["lightek_site_id"].to_s == order.site_id.to_s
      raise Rejected, "Mismatched checkout" unless session.id == order.payment_reference
      raise Rejected, "Mismatched currency" unless session.currency.to_s.downcase == order.currency

      if event.type == "checkout.session.expired"
        raise Rejected, "Expiration not confirmed" unless session.status == "expired"
        return order if order.status != "pending_payment"
        # Protect stock during asynchronous payment or out-of-order event delivery.
        raise Rejected, "Payment state uncertain on expiry" if session.payment_status == "paid"
        OrderPlacement.cancel!(order)
        return order
      end
      return order unless session.mode == "payment" && session.payment_status == "paid"
      order.with_lock do
        if %w[paid fulfilled partially_refunded refunded].include?(order.status)
          # Stripe retries also recover a lost provisioning enqueue after settlement.
          # The provisioning job's order-bound advisory lock prevents duplicate allocation.
          if order.paid_at? && !order.provisioned_at? &&
              order.items.any? { |item| item.product.product_type == "lightek_instance" }
            PaidInstanceProvisioningJob.perform_later(order.id)
          end
          return order
        end
        raise Rejected, "Paid checkout for canceled order requires manual recovery" unless order.status == "pending_payment"
        subtotal = session.amount_subtotal.to_i
        tax = session.total_details.amount_tax.to_i
        shipping = session.total_details.amount_shipping.to_i
        total = session.amount_total.to_i
        raise Rejected, "Mismatched line items" unless subtotal == order.subtotal_cents
        raise Rejected, "Mismatched totals" unless subtotal + tax + shipping == total && total >= subtotal
        order.update!(status: "paid", paid_at: Time.current, tax_cents: tax, shipping_cents: shipping, total_cents: total)
        OrderConfirmationJob.perform_later(order.id)
        PaidInstanceProvisioningJob.perform_later(order.id) if order.items.any? { |item| item.product.product_type == "lightek_instance" }
      end
      order
    end
  end
end
