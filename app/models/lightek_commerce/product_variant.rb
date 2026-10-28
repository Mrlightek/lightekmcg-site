# frozen_string_literal: true
module LightekCommerce
  class ProductVariant < ApplicationRecord
    self.table_name = "lightek_commerce_product_variants"
    belongs_to :product, class_name: "LightekCommerce::Product"
    validates :name, presence: true, length: {maximum: 160}
    validates :sku, uniqueness: {scope: :product_id}, allow_blank: true
    validates :price_cents, :inventory_quantity, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
