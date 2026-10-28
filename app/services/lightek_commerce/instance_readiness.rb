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
      missing = REQUIRED.select { |name| ENV[name].blank? }
      raise Unavailable, "VPS setup is incomplete: #{missing.join(', ')}" if missing.any?
      raise Unavailable, "VPS cost estimate must be positive" unless
        ENV.fetch("LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS").match?(/\A[1-9]\d*\z/)
      raise Unavailable, "Super admin operator missing" unless User.exists?(role: "super_admin")
      raise Unavailable, "No healthy Linode provider available" unless
        ComputeProvider.where(slug: "linode", status: "active", health_status: "healthy").exists?
      true
    end
  end
end
