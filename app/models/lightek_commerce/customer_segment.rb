# frozen_string_literal: true

module LightekCommerce
  class CustomerSegment < ApplicationRecord
    self.table_name = 'lightek_commerce_customer_segments'

    belongs_to :site, class_name: 'DymondSite::Site'
    has_many :discounts, class_name: 'LightekCommerce::Discount', dependent: :restrict_with_error

    before_validation { self.slug = name.to_s.parameterize if slug.blank? }
    validates :name, presence: true, length: {maximum: 80}
    validates :slug, presence: true, uniqueness: {scope: :site_id}
    validates :minimum_orders, :maximum_orders, numericality: {only_integer: true, in: 0..100_000}, allow_nil: true
    validates :minimum_net_spend_cents, numericality: {only_integer: true, in: 0..100_000_000_000}, allow_nil: true
    validate do
      if minimum_orders.nil? && maximum_orders.nil? && minimum_net_spend_cents.nil?
        errors.add(:base, 'Add at least one customer condition')
      end
      if minimum_orders && maximum_orders && minimum_orders > maximum_orders
        errors.add(:maximum_orders, 'must be at least the minimum')
      end
    end

    def self.history_for(site, buyer_id)
      return unless buyer_id

      Order.where(site: site, storefront_buyer_id: buyer_id, status: %w[paid fulfilled partially_refunded],
        purpose: [nil, 'purchase', 'gift_card_redemption']).where.not(paid_at: nil)
        .pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total_cents - refunded_cents), 0)'))
    end

    def includes_history?(history)
      return false unless history

      order_count, spend = history
      (!minimum_orders || order_count >= minimum_orders) &&
        (!maximum_orders || order_count <= maximum_orders) &&
        (!minimum_net_spend_cents || spend >= minimum_net_spend_cents)
    end
  end
end
