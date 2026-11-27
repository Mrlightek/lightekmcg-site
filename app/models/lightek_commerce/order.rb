require_relative '../concerns/growth_attributed'
# frozen_string_literal: true
module LightekCommerce
  class Order < ApplicationRecord
    include GrowthAttributed
    before_validation(on: :create) { self.payment_namespace ||= PaymentIdentity.namespace(site) if site }
    self.table_name = "lightek_commerce_orders"
    attr_readonly :buyer_fee_snapshot, :discount_cents, :discount_name, :shipping_discount_cents, :gift_recipient_email, :gift_deliver_at

    def storefront_buyer_attributes
      has_attribute?(:storefront_buyer_id) ? {storefront_buyer_id: storefront_buyer_id} : {}
    end

    def managed_gift_delivery? = has_attribute?(:gift_recipient_email) && gift_recipient_email.present?

    def gift_card_purchase? = purpose == 'gift_card_purchase'
    def gift_card_redemption? = purpose == 'gift_card_redemption'
    def gift_scope = self[:gift_store_scope].presence || "site-#{site_id}"

    def gift_applied = has_attribute?(:gift_applied_cents) ? self[:gift_applied_cents].to_i : 0
    def cash_paid_cents = total_cents - gift_applied
    def transfer_reversal_required? = buyer_fee_cents.positive? || gift_card_redemption?

    def discount_amount = has_attribute?(:discount_cents) ? self[:discount_cents].to_i : 0
    def shipping_discount_amount = has_attribute?(:shipping_discount_cents) ? self[:shipping_discount_cents].to_i : 0
    def quoted_shipping_charge_cents = shipping_quote&.customer_price_cents.to_i - shipping_discount_amount

    after_update_commit :queue_buyer_fee_reversal, if: -> { saved_change_to_status? && status == 'refunded' }

    def queue_buyer_fee_reversal
      return unless payment_provider != "network" && transfer_reversal_required? && merchant_transfer_ref.present? && defined?(BuyerFeeReversalJob)

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
    scope :receipt_eligible, -> { visible.where(status: %w[paid fulfilled partially_refunded refunded]).where.not(paid_at: nil) }

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
      self.revenue_share_snapshot = RevenueSharing.snapshot_for(site.tenant) if site && !gift_card_purchase? && revenue_share_snapshot.blank? && !%w[subscription_renewal shipping_label creator_support creator_support_renewal agency_membership].include?(purpose)
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
