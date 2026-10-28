# frozen_string_literal: true
module LightekCommerce
  class FulfillmentNotificationJob < ApplicationJob
    queue_as :default
    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order && order.status == "fulfilled"
      order.with_lock do
        return if order.fulfillment_notification_sent_at?
        FulfillmentMailer.fulfilled(order.id).deliver_now
        order.update!(fulfillment_notification_sent_at: Time.current)
      end
    end
  end
end
