# frozen_string_literal: true
module LightekCommerce
  class OrderMailer < ApplicationMailer
    def payment_confirmed(order_id)
      @order = Order.includes(:items).find(order_id)
      raise ArgumentError, "Order not paid" unless %w[paid fulfilled partially_refunded refunded].include?(@order.status)
      if @order.gift_card_purchase? && @order.status == 'fulfilled'
        @gift_card = GiftCard.find_by!(purchase_order: @order)
        @gift_code = @gift_card.display_code if @gift_card.usable?
      end
      mail(to: @order.customer_email, subject: "Payment confirmed — order ##{@order.id}")
    end
  end
end
