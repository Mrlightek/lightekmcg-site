class SubscriptionInfrastructureEntitlement < ApplicationRecord
  belongs_to :subscription_plan, class_name: "DymondBank::SubscriptionPlan"
  belongs_to :provisioning_profile, optional: true
  belongs_to :compute_policy, optional: true

  validates :subscription_plan_id, uniqueness: true
  validates :node_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
