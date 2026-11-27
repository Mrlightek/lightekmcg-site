# frozen_string_literal: true
module LightekCommerce
  class Refunds
    class Invalid < StandardError; end

    def self.full!(order:)
      issue!(order: order, amount_cents: order.total_cents - order.refunded_cents)
    end

    def self.issue!(order:, amount_cents:, idempotency_key: nil, merchandise_return_id: nil)
      amount_cents = Integer(amount_cents)
      if merchandise_return_id
        raise Invalid, 'This payment requires the original order refund workflow.' unless ReturnRefunds.supported?(order)
        idempotency_key = PaymentIdentity.key(order, "merchandise-return-#{merchandise_return_id}")
      end
      if order.payment_provider == "network"
        raise Invalid, "A site-local refund is required for this workflow" if idempotency_key
        NetworkCheckout.action!(order: order, action: "refund", attributes: {amount_cents: amount_cents})
        return order
      end
      if order.gift_card_purchase? || order.gift_card_redemption?
        return GiftRefunds.issue!(order: order, amount_cents: amount_cents)
      end
      order.with_lock do
        if idempotency_key && (existing = order.refunds.find_by(idempotency_key: idempotency_key))
          raise Invalid, "The refund amount differs from the recorded request" if existing.amount_cents != amount_cents

          return existing
        end
        if merchandise_return_id
          record = MerchandiseReturn.where(order_id: order.id).find(merchandise_return_id)
          current_amount = ReturnRefunds.amount_for(order, order.items.find(record.order_item_id), record)
          raise Invalid, 'The return refund amount is unavailable or changed. Review the order and any existing refunds.' unless current_amount == amount_cents
        end
        raise Invalid, "Order is not refundable" unless %w[paid fulfilled partially_refunded].include?(order.status)
        pending = order.refunds.where(status: "pending").exists?
        raise Invalid, "Resolve the pending refund before another request" if pending
        raise Invalid, "Invalid refund amount" unless amount_cents.positive? && amount_cents <= order.total_cents - order.refunded_cents
        if order.buyer_fee_cents.positive?
          if amount_cents != order.total_cents - order.refunded_cents
            raise Invalid, "Buyer-fee orders require a full refund, including the checkout fee."
          end
          if order.merchant_transfer_requested_at? && !order.merchant_transfer_ref?
            raise Invalid, 'Reconcile the pending earnings release before refunding this order.'
          end
        end
        raise Invalid, "Stripe checkout missing" unless %w[stripe stripe_invoice].include?(order.payment_provider) && order.payment_reference.present?
        key = DymondBank::StripeCredentials.secret_key
        raise Invalid, "Stripe is not configured" if key.blank?
        Stripe.api_key = key
        payment_intent = ProcessorPayment.intent!(order: order)

        refund_attributes = {amount_cents: amount_cents,
          idempotency_key: idempotency_key || "commerce-refund-#{order.id}-#{SecureRandom.uuid}"}
        refund_attributes[:merchandise_return_id] = merchandise_return_id if merchandise_return_id
        record = order.refunds.create!(refund_attributes)
        attributes = {payment_intent: payment_intent, amount: amount_cents, reason: "requested_by_customer"}
        attributes[:metadata] = {lightek_return_refund: record.idempotency_key} if merchandise_return_id
        begin
          response = Stripe::Refund.create(attributes, {idempotency_key: record.idempotency_key})
        rescue Stripe::StripeError
          raise unless merchandise_return_id

          # Keep the pending record if Stripe's response is uncertain. Signed events can complete it.
          next record
        end
        record.update!(processor_ref: response.id, status: %w[failed canceled].include?(response.status) ? 'failed' : 'pending')
        if response.status == "succeeded"
          record.update!(status: "succeeded")
          refunded = order.refunded_cents + amount_cents
          order.update!(refunded_cents: refunded,
            status: refunded == order.total_cents ? "refunded" : "partially_refunded")
        end
        record
      end
    rescue LightekReservations::Federation::Client::Unavailable, StripeCheckout::Unavailable => error
      raise Invalid, error.message
    rescue ArgumentError, TypeError
      raise Invalid, "Invalid refund amount"
    end
  end
end
