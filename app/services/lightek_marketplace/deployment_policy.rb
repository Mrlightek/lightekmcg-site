# frozen_string_literal: true

module LightekMarketplace
  # A paid customer gets a dedicated node. Only an explicitly designated
  # free/internal account may use the shared deployment pool.
  module DeploymentPolicy
    class NotEligible < StandardError; end

    def self.target_for(purchase)
      raise NotEligible, "A settled purchase is required" unless purchase.status.in?(%w[paid provisioning provisioned])
      offer = purchase.offer
      config = offer.meta.to_h.fetch("lightek_marketplace", {})
      raise NotEligible, "This is not a managed Marketplace product" unless [88, 89].include?(config["version"])
      return "shared" if offer.mode.to_s == "free" && config["deployment_target"] == "shared"
      "dedicated_vps"
    end

    def self.existing_node_for(customer)
      GatekeeperNode.where(owner: customer).where.not(status: %w[failed decommissioned])
        .order(:id).first
    end
  end
end
