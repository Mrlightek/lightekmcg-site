# frozen_string_literal: true
module LightekCommerce
  class StripeEvents
    class Rejected < StandardError; end

    def self.process!(event)
      return SubscriptionEvents.process!(event) if SubscriptionEvents::TYPES.include?(event.type)
      if %w[charge.refund.updated refund.updated].include?(event.type)
        refund = event.data.object
        return RefundSettlement.call(processor_ref: refund.id, status: refund.status)
      end
      return unless %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired].include?(event.type)
      session = event.data.object
      network_key = session.metadata.to_h.stringify_keys["lightek_network_sale_key"]
      return nil if network_key.present? && !NetworkSale.exists?(public_key: network_key)
      order_id = session.metadata.to_h.stringify_keys["lightek_commerce_order_id"].to_s
      namespace = session.metadata.to_h.stringify_keys['lightek_host_key'].presence
      order = namespace ? Order.find_by(id: order_id, payment_namespace: namespace) : Order.find_by(id: order_id)
      return nil if namespace && !order # Another isolated Lightek installation.
      raise Rejected, "Unknown commerce order" unless order
      raise Rejected, "Mismatched site" unless session.metadata.to_h.stringify_keys["lightek_site_id"].to_s == order.site_id.to_s
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
      return order unless %w[payment subscription].include?(session.mode) && session.payment_status == "paid"
      order.with_lock do
        interval = order.items.first&.purchase_snapshot.to_h.fetch("billing_interval", "one_time")
        raise Rejected, "Checkout billing mode mismatch" unless session.mode == (interval == "one_time" ? "payment" : "subscription")
        SubscriptionEvents.register!(order: order, session: session) if session.mode == "subscription"
        if %w[paid fulfilled partially_refunded refunded].include?(order.status)
          # Stripe retries also recover a lost provisioning enqueue after settlement.
          # The provisioning job's order-bound advisory lock prevents duplicate allocation.
          if order.purpose != "reservation_change" && %w[paid fulfilled].include?(order.status) && order.paid_at? && !order.provisioned_at? &&
              order.items.any? { |item| item.product.product_type == "lightek_instance" }
            PaidInstanceProvisioningJob.perform_later(order.id)
          end
          LightekShipping::LabelJob.perform_later(order.id) if order.purpose == "shipping_label" || (order.shipping_quote && order.shipping_quote.purchase_order_id == order.id)
          next
        end
        raise Rejected, "Paid checkout for canceled order requires manual recovery" unless order.status == "pending_payment"
        quoted_shipping = order.shipping_quote && order.purpose != "shipping_label" ? order.shipping_quote.customer_price_cents : 0
        subtotal = session.amount_subtotal.to_i - quoted_shipping
        tax = session.total_details.amount_tax.to_i
        raise Rejected, "Unexpected extra shipping charge" if quoted_shipping.positive? && session.total_details.amount_shipping.to_i != 0
        shipping = session.total_details.amount_shipping.to_i + quoted_shipping
        total = session.amount_total.to_i
        raise Rejected, "Mismatched line items" unless subtotal == order.subtotal_cents
        raise Rejected, "Mismatched totals" unless subtotal + tax + shipping == total && total >= subtotal
        order.update!(status: "paid", paid_at: Time.current, tax_cents: tax, shipping_cents: shipping, total_cents: total)
        if session.mode == "subscription" && session.respond_to?(:invoice) && session.invoice.present?
          reference = session.invoice.respond_to?(:id) ? session.invoice.id : session.invoice
          BillingInvoice.find_or_create_by!(processor_reference: reference) do |receipt|
            receipt.subscription = order.commerce_subscription
            receipt.settlement_order = order
            receipt.amount_paid_cents = total
            receipt.currency = order.currency
            receipt.paid_at = order.paid_at
          end
        end
        if order.shipping_quote && order.purpose != "shipping_label" && order.shipping_quote.broker_reference.blank?
          order.shipping_quote.update!(purchase_order: order)
          LightekShipping::LabelJob.perform_later(order.id)
        end
        LightekShipping::LabelJob.perform_later(order.id) if order.purpose == "shipping_label"
        RevenueSharing.record!(order)
        OrderConfirmationJob.perform_later(order.id)
        PaidInstanceProvisioningJob.perform_later(order.id) if order.purpose != "reservation_change" && order.items.any? { |item| item.product.product_type == "lightek_instance" }
      end
      LightekReservations::Settlement.for_order!(order)
      order
    end
  end
end
