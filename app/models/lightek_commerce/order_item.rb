# frozen_string_literal: true
module LightekCommerce
  class OrderItem < ApplicationRecord
    self.table_name = "lightek_commerce_order_items"
    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :variant, class_name: "LightekCommerce::ProductVariant", optional: true
    belongs_to :product, class_name: "LightekCommerce::Product"
    validates :quantity, numericality: {only_integer: true, greater_than: 0}
    validates :unit_price_cents, :line_total_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
