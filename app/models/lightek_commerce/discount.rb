# frozen_string_literal: true

module LightekCommerce
  class Discount < ApplicationRecord
    self.table_name = 'lightek_commerce_discounts'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :target_product, class_name: 'LightekCommerce::Product', optional: true
    before_validation { self.code = self.class.normalize(code) }
    validates :name, presence: true, length: {maximum: 100}
    validates :code, format: {with: /\A[A-Z0-9_-]{1,40}\z/}, uniqueness: {scope: :site_id}, allow_nil: true
    validates :kind, inclusion: {in: %w[fixed percent]}
    validates :amount, numericality: {only_integer: true, in: 1..1_000_000}
    validates :amount, numericality: {only_integer: true, in: 1..99}, if: -> { kind == 'percent' }
    validates :minimum_cents, numericality: {only_integer: true, in: 0..100_000_000}

    validates :usage_limit, :buyer_limit, numericality: {only_integer: true, in: 1..1_000_000}, allow_nil: true
    validate do
      if target_product_id && target_product&.site_id != site_id
        errors.add(:target_product, 'must belong to this store')
      end
      if starts_at && ends_at && ends_at <= starts_at
        errors.add(:ends_at, 'must follow the start time')
      end
    end

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
