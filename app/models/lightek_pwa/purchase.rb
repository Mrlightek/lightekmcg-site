module LightekPwa
  class Purchase < ApplicationRecord
    self.table_name = 'lightek_pwa_purchases'
    belongs_to :user
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    validates :order_id, uniqueness: true
    validates :plan_key, inclusion: {in: %w[personal business]}
    def entitled?
      return false if user.respond_to?(:access_active?) && !user.access_active?
      return false if Membership.where(site_id: site_id, profile_id: user.profile&.id, status: 'suspended').exists?
      subscription = order.commerce_subscription
      order.site_id == site_id && order.paid_at? && %w[paid fulfilled].include?(order.status) &&
        !order.refunds.where(status: 'succeeded').exists? && !order.refunds.where(status: 'pending').exists? &&
        subscription && subscription.status == 'active' && subscription.current_period_end&.future?
    end
  end
end
