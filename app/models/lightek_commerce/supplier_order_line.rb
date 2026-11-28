# frozen_string_literal: true

module LightekCommerce
  class SupplierOrderLine < ApplicationRecord
    self.table_name = 'lightek_commerce_supplier_order_lines'

    belongs_to :supplier_order, class_name: 'LightekCommerce::SupplierOrder'
    def remaining_quantity = ordered_quantity - received_quantity
  end
end
