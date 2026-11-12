module LightekShipping
  class LabelJob < ApplicationJob
    queue_as :default
    def perform(order_id)
      order = LightekCommerce::Order.find(order_id)
      quote = Quote.find_by(purchase_order_id: order.id)
      return unless quote && order.paid_at? && %w[paid fulfilled].include?(order.status)
      Labels.issue!(quote: quote)
    end
  end
end
