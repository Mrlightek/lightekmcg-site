module LightekPwa
  class CreatorPayment < ApplicationRecord
    self.table_name = 'lightek_pwa_creator_payments'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :creator, class_name: 'User'
    belongs_to :supporter, class_name: 'User'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    belongs_to :post, optional: true
    has_many :earnings, class_name: 'LightekPwa::CreatorEarning', dependent: :restrict_with_error
    validates :kind, inclusion: {in: %w[subscription tip gift]}
    validates :request_key, format: {with: /\A[0-9a-f-]{36}\z/i}
    validates :principal_cents, numericality: {only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 100_000}
    validates :fee_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    def active_subscription?
      subscription = order.commerce_subscription
      kind == 'subscription' && order.paid_at? && %w[paid fulfilled].include?(order.status) &&
        !order.refunds.where(status: %w[pending succeeded]).exists? && subscription&.status == 'active' && subscription.current_period_end&.future?
    end
  end
end
