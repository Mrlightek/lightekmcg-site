# frozen_string_literal: true
module LightekCommerce
  class Refund < ApplicationRecord
    self.table_name = "lightek_commerce_refunds"
    belongs_to :order, class_name: "LightekCommerce::Order"
    validates :amount_cents, numericality: {only_integer: true, greater_than: 0}
    validates :idempotency_key, presence: true, uniqueness: true
    validates :status, inclusion: {in: %w[pending succeeded failed]}
  end
end
