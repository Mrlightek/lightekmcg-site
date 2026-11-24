module ItServices
  class Membership < ApplicationRecord
    self.table_name = "it_service_memberships"

    belongs_to :plan
    belongs_to :customer, class_name: "User"
    belongs_to :order, class_name: "LightekCommerce::Order"
    has_many :coverage_periods, foreign_key: :membership_id, dependent: :restrict_with_error

    attr_readonly :plan_id, :customer_id, :order_id

    scope :open, -> { joins(:order).where(lightek_commerce_orders: { status: %w[pending_payment paid fulfilled partially_refunded] }) }

    def subscription = order.commerce_subscription

    def cancellable?
      subscription && !subscription.status.in?(%w[canceled incomplete_expired]) && !subscription.cancel_at_period_end?
    end
  end
end
