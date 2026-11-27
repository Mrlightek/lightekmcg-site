# frozen_string_literal: true

module LightekCommerce
  class MerchandiseReturn < ApplicationRecord
    self.table_name = 'lightek_commerce_merchandise_returns'

    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :order_item, class_name: 'LightekCommerce::OrderItem'
    validates :reason, presence: true, length: {maximum: 300}

    scope :counting_against_order, -> { where(status: %w[requested approved received]) }
  end
end
