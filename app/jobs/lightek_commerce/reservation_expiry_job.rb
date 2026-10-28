# frozen_string_literal: true
module LightekCommerce
  class ReservationExpiryJob < ApplicationJob
    queue_as :default

    # Inventory is released only after Stripe confirms an expired, unpaid
    # checkout. A completed-but-unpaid session may still settle asynchronously.
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order&.status == "pending_payment"
      return if order.created_at > 35.minutes.ago

      unless order.payment_reference.present?
        OrderPlacement.cancel!(order)
        return
      end

      key = DymondBank::StripeCredentials.secret_key
      raise "Stripe credentials unavailable: cannot reconcile stock" if key.blank?

      Stripe.api_key = key
      session = Stripe::Checkout::Session.retrieve(order.payment_reference)
      if session.payment_status == "paid"
        StripeEvents.process!(Struct.new(:type, :data).new(
          "checkout.session.completed", Struct.new(:object).new(session)))
      elsif session.status == "open"
        expired = Stripe::Checkout::Session.expire(session.id)
        raise "Checkout expiry could not be confirmed" unless expired.status == "expired" && expired.payment_status != "paid"
        OrderPlacement.cancel!(order) if order.reload.status == "pending_payment"
      elsif session.status == "expired" && session.payment_status != "paid"
        OrderPlacement.cancel!(order) if order.reload.status == "pending_payment"
      else
        # Completed unpaid checkout, async processor, or unknown state:
        # never release inventory before payment reconciliation.
        raise "Checkout still settling; stock retained (#{session.status}/#{session.payment_status})"
      end
    end
  end
end
