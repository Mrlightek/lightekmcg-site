# frozen_string_literal: true

require "json"
require "securerandom"

module LightekCommunications
  class CellularBundle
    DEFAULT_GATEWAY_RECOVERY_CENTS = 10_000
    DEFAULT_PLANNED_PAYING_LINES = 4

    def self.offer(product, peer:)
      return unless peer&.active? && product.communications_kind == "voice" &&
        product.billing_interval == "month" && product.currency == "usd"

      policy = config
      plans = policy["plans"]
      peers = policy["peers"]
      plan = plans[product.slug] if plans.is_a?(Hash)
      ip = peers[peer.key] if peers.is_a?(Hash)
      return unless UserEsim.host_ipv4?(ip) && VoiceSetup.route(peer)&.fetch("managed", false)

      configured_offer(product, plan: plan, policy: policy)&.merge("peer_ip" => ip)
    end

    def self.configured_offer(product, plan:, policy:)
      group_id = ENV["TELNYX_SIM_CARD_GROUP_ID"]
      return unless plan.is_a?(Hash) && UserEsim::UUID.match?(group_id.to_s)
      return unless %w[TELNYX_API_KEY TELNYX_PUBLIC_KEY HUB_VPS_HOST HUB_VPS_USER HUB_VPS_SSH_KEY HUB_VPS_KNOWN_HOSTS_FILE].all? { |key| ENV[key].present? }

      limit = plan["data_limit_mb"]
      floor = minimum_price_cents(policy, monthly_cost_cents: plan["monthly_cost_cents"])
      return unless limit.is_a?(Integer) && limit.between?(1, 2_147_483_647) &&
        floor && product.price_cents >= floor

      { "data_limit_mb" => limit, "group_id" => group_id.downcase }
    end

    def self.minimum_price_cents(policy, monthly_cost_cents:)
      gateway = policy.fetch("gateway_recovery_cents", DEFAULT_GATEWAY_RECOVERY_CENTS)
      lines = policy.fetch("planned_paying_lines", DEFAULT_PLANNED_PAYING_LINES)
      fixed = policy["billing_fee_cents"]
      fee = policy["billing_fee_basis_points"]
      margin = policy["target_margin_basis_points"]
      return unless [gateway, lines, fixed, fee, margin, monthly_cost_cents].all? { |value| value.is_a?(Integer) && value >= 0 }
      return unless lines.positive? && monthly_cost_cents.positive? && fee + margin < 10_000

      share = (gateway + lines - 1).div(lines)
      numerator = (monthly_cost_cents + share + fixed) * 10_000
      denominator = 10_000 - fee - margin
      (numerator + denominator - 1).div(denominator)
    end

    def self.config
      policy = JSON.parse(ENV.fetch("LIGHTEK_CELLULAR_BUNDLES", "{}"))
      policy.is_a?(Hash) ? policy : {}
    rescue JSON::ParserError
      {}
    end

    def initialize(add_on)
      @add_on = add_on
    end

    def esim
      UserEsim.find_by(request_key: @add_on.cellular_request_key, user_id: @add_on.peer.merchant_id)
    end

    def allowance
      @add_on.order.items.sole.purchase_snapshot.dig("cellular_bundle", "data_limit_mb")
    end

    def paid?
      peer = @add_on.peer
      subscription = @add_on.order.commerce_subscription
      @add_on.cellular_request_key.present? && peer.active? && LightekPeople::LifecycleAccess.active?(peer.merchant) &&
        subscription && Fulfillment.billing_receipt(subscription).present?
    end

    def status
      record = esim
      { status: record&.status || "provisioning", data_limit_mb: allowance,
        activation_available: paid? && record&.activation_requested_at? && record[:lpa_activation_code].present? }
    end

    def activation!
      record = esim
      unless paid? && record&.activation_requested_at? && record[:lpa_activation_code].present?
        raise InstallationVoice::Unavailable, "Your eSIM is still being prepared."
      end

      { apn: "data.net", qr_png_base64: record.activation_qr_base64 }
    end

    def provision!
      return unless paid?
      return if esim&.route_installed_at?

      Telnyx::ProvisionEsimService.call(user: @add_on.peer.merchant, sim_card_group_id: @add_on.cellular_group_id,
        plan_limit_mb: allowance, customer_wg_peer_ip: @add_on.cellular_peer_ip, request_key: @add_on.cellular_request_key)
    end
  end
end
