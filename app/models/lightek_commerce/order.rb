require_relative '../concerns/growth_attributed'
# frozen_string_literal: true
module LightekCommerce
  class Order < ApplicationRecord
    include GrowthAttributed
    before_validation(on: :create) { self.payment_namespace ||= PaymentIdentity.namespace(site) if site }
    self.table_name = "lightek_commerce_orders"
    attr_readonly :buyer_fee_snapshot
    after_update_commit :queue_buyer_fee_reversal, if: -> { saved_change_to_status? && status == 'refunded' }

    def queue_buyer_fee_reversal
      return unless payment_provider != "network" && buyer_fee_cents.positive? && merchant_transfer_ref.present? && defined?(BuyerFeeReversalJob)

      BuyerFeeReversalJob.perform_later(id)
    rescue StandardError => error
      Rails.logger.warn("Buyer fee refund reconciliation enqueue failed for order #{id}: #{error.class}")
    end
    private :queue_buyer_fee_reversal

    def buyer_fee_breakdown
      has_attribute?(:buyer_fee_snapshot) ? buyer_fee_snapshot.to_h : {}
    end

    def buyer_fee_cents
      buyer_fee_breakdown.fetch('network_cents', 0) + buyer_fee_breakdown.fetch('processor_reserve_cents', 0)
    end

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
      self.revenue_share_snapshot = RevenueSharing.snapshot_for(site.tenant) if site && revenue_share_snapshot.blank? && !%w[subscription_renewal shipping_label creator_support creator_support_renewal agency_membership].include?(purpose)
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
