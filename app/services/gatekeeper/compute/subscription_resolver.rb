module Gatekeeper
  module Compute
    class SubscriptionResolver
      Resolution = Data.define(:subscription, :plan, :entitlement, :profile, :policy, :node_quantity, :auto_provision)

      def self.call(subscriber:)
        subscription = DymondBank::Subscription
          .where(subscriber: subscriber)
          .where(status: %w[trialing active])
          .order(created_at: :desc)
          .first
        return unless subscription

        entitlement = SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id: subscription.plan_id)

        Resolution.new(
          subscription,
          subscription.plan,
          entitlement,
          entitlement&.provisioning_profile,
          entitlement&.compute_policy,
          entitlement&.node_quantity.to_i,
          entitlement&.auto_provision? || false
        )
      end
    end
  end
end
