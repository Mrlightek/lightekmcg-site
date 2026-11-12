module LightekCommerce
  class RevenueAllocation < ApplicationRecord
    self.table_name = "lightek_commerce_revenue_allocations"
    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :beneficiary, class_name: "User"
    validates :beneficiary_id, uniqueness: {scope: :order_id}
    validates :amount_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :status, inclusion: {in: %w[pending retained transferred]}
  end
end
