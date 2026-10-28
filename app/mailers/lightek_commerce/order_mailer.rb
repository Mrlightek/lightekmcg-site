# frozen_string_literal: true
module LightekCommerce
  class OrderMailer < ApplicationMailer
    def payment_confirmed(order_id)
      @order = Order.includes(:items).find(order_id)
      raise ArgumentError, "Order not paid" unless %w[paid fulfilled partially_refunded refunded].include?(@order.status)
      mail(to: @order.customer_email, subject: "Payment confirmed — order ##{@order.id}")
    end
  end
end
