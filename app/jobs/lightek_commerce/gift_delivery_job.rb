# frozen_string_literal: true

module LightekCommerce
  class GiftDeliveryJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order

      order.with_lock do
        return unless order.gift_card_purchase? && order.managed_gift_delivery? && order.paid_at? &&
          order.status == 'fulfilled' && !order.gift_delivered_at?

        if order.gift_deliver_at&.future?
          GiftDelivery.enqueue(order)
          return
        end

        card = GiftCard.find_by!(purchase_order: order)
        card.with_lock do
          return unless card.usable?

          OrderMailer.gift_delivered(order.id).deliver_now
          order.update!(gift_delivered_at: Time.current)
        end
      end
    end
  end
end
