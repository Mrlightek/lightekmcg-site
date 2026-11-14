# frozen_string_literal: true
module LightekCommerce
  class Order < ApplicationRecord
    before_validation(on: :create) { self.payment_namespace ||= PaymentIdentity.namespace(site) if site }
    self.table_name = "lightek_commerce_orders"
    scope :visible, -> { where(deleted_at: nil) }

    def removable?
      %w[pending_payment canceled].include?(status) && !paid_at? && !provisioned_at? && gatekeeper_application_launch_id.nil?
    end
    belongs_to :site, class_name: "DymondSite::Site"
    has_one :network_sale, class_name: "LightekCommerce::NetworkSale", dependent: :restrict_with_error
    has_one :commerce_subscription, class_name: "LightekCommerce::Subscription", dependent: :restrict_with_error
    belongs_to :gatekeeper_application_launch, optional: true
    belongs_to :shipping_quote, class_name: "LightekShipping::Quote", optional: true
    belongs_to :hosting_owner, class_name: "User", optional: true
    has_many :revenue_allocations, class_name: "LightekCommerce::RevenueAllocation", dependent: :restrict_with_error
    before_validation(on: :create) do
      self.revenue_share_snapshot = RevenueSharing.snapshot_for(site.tenant) if site && revenue_share_snapshot.blank? && !%w[subscription_renewal shipping_label].include?(purpose)
    end
    has_many :items, class_name: "LightekCommerce::OrderItem", dependent: :restrict_with_error
    STATUSES = %w[pending_payment paid fulfilled canceled partially_refunded refunded].freeze
    has_many :refunds, class_name: 'LightekCommerce::Refund', dependent: :restrict_with_error
    validates :status, inclusion: {in: STATUSES}
    validates :customer_email, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}
    validates :currency, inclusion: {in: %w[usd]}
    validates :total_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
