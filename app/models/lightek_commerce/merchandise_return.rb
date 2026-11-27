# frozen_string_literal: true

module LightekCommerce
  class MerchandiseReturn < ApplicationRecord
    self.table_name = 'lightek_commerce_merchandise_returns'

    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :order_item, class_name: 'LightekCommerce::OrderItem'
    validates :reason, presence: true, length: {maximum: 300}

    QUEUE_FILTERS = {
      'open' => %w[requested approved],
      'requested' => ['requested'],
      'approved' => ['approved'],
      'received' => ['received'],
      'closed' => %w[rejected canceled]
    }.freeze
    PAGE_SIZE = 50

    def self.queue(site:, filter:, before_id: nil)
      owned_orders = Order.receipt_eligible.where(site: site)
        .where(status: %w[fulfilled partially_refunded refunded])
        .where("fulfilled_at IS NOT NULL OR status = 'fulfilled'")
      scope = where(order_id: owned_orders.select(:id), status: QUEUE_FILTERS.fetch(filter))
      scope = scope.where(id: ...before_id) if before_id
      scope.includes(:order_item).order(id: :desc).limit(PAGE_SIZE + 1).to_a
    end

    scope :counting_against_order, -> { where(status: %w[requested approved received]) }
  end
end
