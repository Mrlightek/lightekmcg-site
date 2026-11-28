# frozen_string_literal: true

module LightekCommerce
  class Discount < ApplicationRecord
    self.table_name = 'lightek_commerce_discounts'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :target_product, class_name: 'LightekCommerce::Product', optional: true
    belongs_to :target_collection, class_name: 'LightekCommerce::Collection', optional: true
    belongs_to :qualifying_product, class_name: 'LightekCommerce::Product', optional: true
    belongs_to :qualifying_collection, class_name: 'LightekCommerce::Collection', optional: true
    belongs_to :customer_segment, class_name: 'LightekCommerce::CustomerSegment', optional: true
    before_validation { self.code = self.class.normalize(code) }
    validates :name, presence: true, length: {maximum: 100}
    validates :code, format: {with: /\A[A-Z0-9_-]{1,40}\z/}, uniqueness: {scope: :site_id}, allow_nil: true
    validates :kind, inclusion: {in: %w[fixed percent buy_x_get_y]}
    validates :amount, numericality: {only_integer: true, in: 1..1_000_000}
    validates :amount, numericality: {only_integer: true, in: 1..99}, if: -> { kind == 'percent' }
    validates :minimum_cents, numericality: {only_integer: true, in: 0..100_000_000}

    validates :usage_limit, :buyer_limit, numericality: {only_integer: true, in: 1..1_000_000}, allow_nil: true
    validates :buy_quantity, :get_quantity, numericality: {only_integer: true, in: 1..5000}, if: :quantity_promotion?
    validates :applications_per_order, numericality: {only_integer: true, in: 1..5000}, allow_nil: true
    validates :reward_type, inclusion: {in: %w[percent fixed]}, if: :quantity_promotion?
    with_options if: -> { quantity_promotion? && reward_type == 'percent' } do
      validates :amount, numericality: {only_integer: true, in: 1..100}
    end

    validate do
      if target_product_id && target_product&.site_id != site_id
        errors.add(:target_product, 'must belong to this store')
      end
      if target_collection_id && (target_product_id || target_collection&.site_id != site_id)
        errors.add(:target_collection, 'must be from this store and selected without a product target')
      end
      if qualifying_product_id && (qualifying_collection_id || qualifying_product&.site_id != site_id)
        errors.add(:qualifying_product, 'must be from this store and selected without a qualifying collection')
      end
      if qualifying_collection_id && qualifying_collection&.site_id != site_id
        errors.add(:qualifying_collection, 'must belong to this store')
      end
      if quantity_promotion? && target_product_id.nil? && target_collection_id.nil?
        errors.add(:base, 'Select a reward product or collection for Buy X Get Y')
      end
      if customer_segment_id && customer_segment&.site_id != site_id
        errors.add(:customer_segment, 'must belong to this store')
      end
      if starts_at && ends_at && ends_at <= starts_at
        errors.add(:ends_at, 'must follow the start time')
      end
    end

    def quantity_promotion? = kind == 'buy_x_get_y'

    def scheduled_for?(at)
      (!starts_at || starts_at <= at) && (!ends_at || ends_at > at)
    end

    def self.normalize(code) = code.to_s.strip.upcase.presence

    def savings(base, cart_subtotal:)
      return 0 if cart_subtotal < minimum_cents || base.zero?

      value = kind == 'percent' ? base * amount / 100 : amount
      [value, base].min
    end
  end
end
