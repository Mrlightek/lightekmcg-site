# frozen_string_literal: true

module LightekCommerce
  class SupplierOrder < ApplicationRecord
    self.table_name = 'lightek_commerce_supplier_orders'

    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :lines, class_name: 'LightekCommerce::SupplierOrderLine', dependent: :restrict_with_error
    validates :supplier, presence: true, length: {maximum: 160}
    validates :invoice_reference, length: {maximum: 160}, allow_nil: true

    def received_subtotal_cents
      lines.sum('received_quantity * unit_cost_cents')
    end
  end
end
