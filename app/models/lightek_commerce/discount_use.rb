# frozen_string_literal: true

module LightekCommerce
  class DiscountUse < ApplicationRecord
    self.table_name = 'lightek_commerce_discount_uses'
    belongs_to :discount, class_name: 'LightekCommerce::Discount'
    belongs_to :order, class_name: 'LightekCommerce::Order'

    scope :counted, -> { joins(:order).where.not(lightek_commerce_orders: {status: 'canceled'}) }
  end
end
