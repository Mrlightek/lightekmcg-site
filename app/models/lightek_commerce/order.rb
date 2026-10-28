# frozen_string_literal: true
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = "lightek_commerce_orders"
    belongs_to :site, class_name: "DymondSite::Site"
    has_many :items, class_name: "LightekCommerce::OrderItem", dependent: :restrict_with_error
    STATUSES = %w[pending_payment paid fulfilled canceled partially_refunded refunded].freeze
    has_many :refunds, class_name: 'LightekCommerce::Refund', dependent: :restrict_with_error
    validates :status, inclusion: {in: STATUSES}
    validates :customer_email, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}
    validates :currency, inclusion: {in: %w[usd]}
    validates :total_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
