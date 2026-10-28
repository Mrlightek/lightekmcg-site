# frozen_string_literal: true
module LightekCommerce
  class Refunds
    class Invalid < StandardError; end
    def self.full!(order:)
      order.with_lock do
        raise Invalid, "Only paid orders can be refunded" unless order.status == "paid"
        raise Invalid, "No Stripe checkout reference" unless order.payment_provider == "stripe" && order.payment_reference.present?
        Stripe.api_key = DymondBank::StripeCredentials.secret_key
        session = Stripe::Checkout::Session.retrieve(order.payment_reference)
        raise Invalid, "Payment intent unavailable" if session.payment_intent.blank?
        refund = Stripe::Refund.create({payment_intent: session.payment_intent, reason: "requested_by_customer"},
          {idempotency_key: "lightek-commerce-order-#{order.id}-refund"})
        raise Invalid, "Refund is not confirmed" unless refund.status == "succeeded"
        order.update!(status: "refunded")
        refund
      end
    end
  end
end
