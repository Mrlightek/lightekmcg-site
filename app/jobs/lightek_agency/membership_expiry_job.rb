module LightekAgency
  class MembershipExpiryJob < ApplicationJob
    queue_as :default

    def perform(trial_id = nil)
      return Trial.find_by(id: trial_id)&.expire_membership! if trial_id

      Trial.joins(:prospect, :paid_order).where(users: {role: 'white_label'})
        .where('paid_through <= :now OR lightek_commerce_orders.status = :refunded', now: Time.current, refunded: 'refunded')
        .find_each(&:expire_membership!)
    end
  end
end
