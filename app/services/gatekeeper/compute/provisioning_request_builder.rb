module Gatekeeper
  module Compute
    class ProvisioningRequestBuilder
      class NoInfrastructureEntitlement < StandardError; end

      def self.call(subscription:, estimated_monthly_cost_cents: nil, requested_by: "system")
        new(
          subscription: subscription,
          estimated_monthly_cost_cents: estimated_monthly_cost_cents,
          requested_by: requested_by
        ).call
      end

      def initialize(subscription:, estimated_monthly_cost_cents:, requested_by:)
        @subscription = subscription
        @estimated_monthly_cost_cents = estimated_monthly_cost_cents
        @requested_by = requested_by
      end

      def call
        subscriber = subscription.subscriber
        resolution = SubscriptionResolver.call(subscriber: subscriber)

        unless resolution&.entitlement
          raise NoInfrastructureEntitlement,
                "Subscription plan #{subscription.plan_id} has no infrastructure entitlement"
        end

        entitlement = resolution.entitlement
        provider, provider_error = select_provider(resolution.policy)

        request = ProvisioningRequest.create!(
          owner: subscriber,
          subscription: subscription,
          subscription_plan: subscription.plan,
          subscription_infrastructure_entitlement: entitlement,
          provisioning_profile: resolution.profile,
          compute_policy: resolution.policy,
          compute_provider: provider,
          requested_node_count: [resolution.node_quantity.to_i, 1].max,
          estimated_monthly_cost_cents: estimated_monthly_cost_cents,
          approval_status: "pending",
          execution_status: initial_execution_status(provider, estimated_monthly_cost_cents),
          metadata: {
            "requested_by" => requested_by,
            "auto_provision" => resolution.auto_provision,
            "provider_selection_error" => provider_error
          }.compact
        )

        ApprovalService.call(request: request, requested_by: requested_by)
      end

      private

      attr_reader :subscription, :estimated_monthly_cost_cents, :requested_by

      def select_provider(policy)
        return [nil, "No compute policy configured"] unless policy

        [ProviderSelector.call(policy: policy), nil]
      rescue StandardError => e
        [nil, "#{e.class}: #{e.message}"]
      end

      def initial_execution_status(provider, estimated_cost)
        return "awaiting_provider" unless provider
        return "awaiting_cost" if estimated_cost.nil?
        "awaiting_approval"
      end
    end
  end
end
