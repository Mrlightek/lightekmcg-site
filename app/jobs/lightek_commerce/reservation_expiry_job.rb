# frozen_string_literal: true
module LightekCommerce
  class ReservationExpiryJob < ApplicationJob
    queue_as :default
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order&.status == "pending_payment"
      return if order.created_at > 35.minutes.ago
      if order.payment_reference.present?
        key = DymondBank::StripeCredentials.secret_key
        raise "Stripe credentials unavailable: cannot safely release inventory" if key.blank?
        Stripe.api_key = key
        session = Stripe::Checkout::Session.retrieve(order.payment_reference)
        if session.payment_status == "paid"
          LightekCommerce::StripeEvents.process!(Struct.new(:type, :data).new(
            "checkout.session.completed", Struct.new(:object).new(session)))
          return
        end
        if session.status == "open"
          Stripe::Checkout::Session.expire(session.id)
        elsif session.status != "expired"
          raise "Checkout status uncertain: #{session.status}"
        end
      end
      OrderPlacement.cancel!(order) if order.reload.status == "pending_payment"
    end
  end
end
