# frozen_string_literal: true
module LightekCommerce
  # Reject an installation checkout before money is collected when the known
  # provider prerequisites have not been configured.
  class InstanceReadiness
    class Unavailable < StandardError; end

    REQUIRED = %w[LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS LIGHTEK_AUTO_VPS_REGION
                  LIGHTEK_AUTO_VPS_PLAN LIGHTEK_AUTO_VPS_IMAGE].freeze

    def self.check!(order:)
      return true unless order.items.any? { |item| item.product.product_type == "lightek_instance" }

      raise Unavailable, "Installation must be purchased as one separate item" unless
        order.items.size == 1 && order.items.first.quantity == 1
      item = order.items.first
      raise Unavailable, "No subscription plan is configured for this installation" if
        item.product.subscription_plan_id.blank?
      raise Unavailable, "Installation plan is unavailable" unless
        DymondBank::SubscriptionPlan.exists?(id: item.product.subscription_plan_id)
      reservation = LightekReservations::Reservation.find_by(order_id: order.id)
      change = LightekReservations::Change.find_by(order_id: order.id)
      snapshot = reservation&.package_snapshot || change&.quote&.fetch('target', nil)
      cost = snapshot ? snapshot.fetch('compute').fetch('monthly_cost_cents').to_i : ENV.fetch('LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS', '0').to_i
      missing = (snapshot ? [] : REQUIRED).select { |name| ENV[name].blank? }
      raise Unavailable, "VPS setup is incomplete: #{missing.join(', ')}" if missing.any?
      raise Unavailable, "VPS cost estimate must be positive" unless
        cost.positive?
      entitlement = SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id: item.product.subscription_plan_id)
      raise Unavailable, "Installation plan has no infrastructure entitlement" unless entitlement
      policy = entitlement.compute_policy
      raise Unavailable, "Automatic VPS approval is not configured" unless policy&.active? && !policy.approval_required_for?(cost)
      raise Unavailable, "VPS monthly estimate exceeds policy" if policy.monthly_cost_ceiling_cents.present? && cost > policy.monthly_cost_ceiling_cents
      raise Unavailable, "Super admin operator missing" unless User.exists?(role: "super_admin")
      begin
        provider = Gatekeeper::Compute::ProviderSelector.call(policy: policy)
      rescue Gatekeeper::Compute::ProviderSelector::NoEligibleProvider
        raise Unavailable, "No eligible compute provider available for installation plan"
      end
      raise Unavailable, "Automatic installation requires a healthy Linode provider" unless
        provider.slug == "linode" && provider.health_status == "healthy"
      if snapshot
        compute = snapshot.fetch('compute')
        selected = provider.adapter(requested_by: 'reservation-readiness').plans.find { |plan| plan['id'] == compute.fetch('plan') }
        raise Unavailable, 'Selected server plan is unavailable' unless selected
        require 'bigdecimal'
        actual_cost = (BigDecimal(selected.fetch('price').fetch('monthly').to_s) * 100).ceil
        raise Unavailable, 'Configured infrastructure reserve is below the provider cost' if cost < actual_cost
      end
      true
    end
  end
end
