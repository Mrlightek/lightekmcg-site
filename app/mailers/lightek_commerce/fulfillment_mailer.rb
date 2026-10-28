# frozen_string_literal: true
module LightekCommerce
  class FulfillmentMailer < ApplicationMailer
    def fulfilled(order_id)
      @order = Order.find(order_id)
      raise ArgumentError, "Order is not fulfilled" unless @order.status == "fulfilled"
      mail(to: @order.customer_email, subject: "Order ##{@order.id} fulfillment update")
    end
  end
end
