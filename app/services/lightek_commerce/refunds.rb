# frozen_string_literal: true
module LightekCommerce
  class Refunds
    class Invalid < StandardError; end

    def self.full!(order:)
      issue!(order: order, amount_cents: order.total_cents - order.refunded_cents)
    end

    def self.issue!(order:, amount_cents:)
      amount_cents = Integer(amount_cents)
      if order.payment_provider == "network"
        NetworkCheckout.action!(order: order, action: "refund", attributes: {amount_cents: amount_cents})
        return order
      end
      order.with_lock do
        raise Invalid, "Order is not refundable" unless %w[paid fulfilled partially_refunded].include?(order.status)
        pending = order.refunds.where(status: "pending").exists?
        raise Invalid, "Resolve the pending refund before another request" if pending
        raise Invalid, "Invalid refund amount" unless amount_cents.positive? && amount_cents <= order.total_cents - order.refunded_cents
        raise Invalid, "Stripe checkout missing" unless %w[stripe stripe_invoice].include?(order.payment_provider) && order.payment_reference.present?
        key = DymondBank::StripeCredentials.secret_key
        raise Invalid, "Stripe is not configured" if key.blank?
        Stripe.api_key = key
        payment_intent = ProcessorPayment.intent!(order: order)

        record = order.refunds.create!(amount_cents: amount_cents,
          idempotency_key: "commerce-refund-#{order.id}-#{SecureRandom.uuid}")
        response = Stripe::Refund.create({payment_intent: payment_intent, amount: amount_cents,
          reason: "requested_by_customer"}, {idempotency_key: record.idempotency_key})
        record.update!(processor_ref: response.id, status: "pending")
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
