# frozen_string_literal: true
module LightekCommerce
  class OrderConfirmationJob < ApplicationJob
    queue_as :default
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order
      order.with_lock do
        return if order.confirmation_sent_at? || !%w[paid fulfilled partially_refunded refunded].include?(order.status)
        # Mail is queued within the lock. A delivery failure does not silently
        # transition a payment to unpaid.
        OrderMailer.payment_confirmed(order.id).deliver_now
        order.update!(confirmation_sent_at: Time.current)
      end
    end
  end
end
