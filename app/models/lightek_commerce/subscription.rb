module LightekCommerce
  class Subscription < ApplicationRecord
    self.table_name = "lightek_commerce_subscriptions"
    belongs_to :order, class_name: "LightekCommerce::Order"
    belongs_to :bank_subscription, class_name: "DymondBank::Subscription", optional: true
    has_many :billing_invoices, class_name: "LightekCommerce::BillingInvoice", dependent: :restrict_with_error
    validates :processor_reference, uniqueness: true, presence: true
    validates :billing_interval, inclusion: {in: %w[month year]}
    validates :amount_cents, numericality: {only_integer: true, greater_than: 0}
    scope :for_sites, ->(sites) { joins(:order).where(lightek_commerce_orders: {site_id: sites.select(:id)}) }
  end
end
