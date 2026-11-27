# frozen_string_literal: true

module LightekCommerce
  class GiftRedemption < ApplicationRecord
    self.table_name = 'lightek_commerce_gift_redemptions'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :gift_card, class_name: 'LightekCommerce::GiftCard'
  end
end
