# frozen_string_literal: true
module LightekCommerce
  class ReservationExpiryJob < ApplicationJob
    queue_as :default
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order && order.status == "pending_payment"
      return if order.created_at > 30.minutes.ago
      OrderPlacement.cancel!(order)
    end
  end
end
