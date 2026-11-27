# frozen_string_literal: true

module LightekCommerce
  class Discount < ApplicationRecord
    self.table_name = 'lightek_commerce_discounts'
    belongs_to :site, class_name: 'DymondSite::Site'
    before_validation { self.code = self.class.normalize(code) }
    validates :name, presence: true, length: {maximum: 100}
    validates :code, format: {with: /\A[A-Z0-9_-]{1,40}\z/}, uniqueness: {scope: :site_id}, allow_nil: true
    validates :kind, inclusion: {in: %w[fixed percent]}
    validates :amount, numericality: {only_integer: true, in: 1..1_000_000}
    validates :amount, numericality: {only_integer: true, in: 1..99}, if: -> { kind == 'percent' }
    validates :minimum_cents, numericality: {only_integer: true, in: 0..100_000_000}

    def self.normalize(code) = code.to_s.strip.upcase.presence

    def savings(subtotal)
      return 0 if subtotal < minimum_cents || subtotal <= 50

      value = kind == 'percent' ? subtotal * amount / 100 : amount
      [value, subtotal - 50].min
    end
  end
end
