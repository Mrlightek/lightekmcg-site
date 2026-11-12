module LightekCommerce
  class BillingInvoice < ApplicationRecord
    self.table_name = "lightek_commerce_billing_invoices"
    belongs_to :subscription, class_name: "LightekCommerce::Subscription"
    belongs_to :settlement_order, class_name: "LightekCommerce::Order", optional: true
    validates :processor_reference, uniqueness: true, presence: true
    validates :amount_paid_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
