# frozen_string_literal: true

module Telnyx
  class ProvisionEsimService
    class Invalid < StandardError; end

    def self.call(user:, sim_card_group_id:, plan_limit_mb:, customer_wg_peer_ip:, request_key:)
      unless UserEsim::UUID.match?(request_key.to_s) && UserEsim::UUID.match?(sim_card_group_id.to_s) &&
          sim_card_group_id.downcase == ENV.fetch("TELNYX_SIM_CARD_GROUP_ID").downcase
        raise Invalid, "A request UUID and the configured private SIM group are required"
      end

      attributes = { user: user, sim_card_group_id: sim_card_group_id.downcase,
        plan_limit_mb: plan_limit_mb, customer_wg_peer_ip: customer_wg_peer_ip }
      esim = UserEsim.create_or_find_by!(request_key: request_key.downcase) do |record|
        record.assign_attributes(attributes)
        record.initial_plan_limit_mb = record.plan_limit_mb
      end
      unless esim.user_id == user.id && esim.sim_card_group_id == attributes[:sim_card_group_id] &&
          esim.customer_wg_peer_ip == customer_wg_peer_ip && esim.initial_plan_limit_mb == Integer(plan_limit_mb.to_s, 10, exception: false)
        raise Invalid, "That request UUID is associated with a different order"
      end

      ProvisionEsimJob.perform_later(esim.id) unless esim.route_installed_at?
      esim
    end

    def initialize(esim, client: WirelessClient.new, hub: CellularHub.new)
      @esim = esim
      @client = client
      @hub = hub
    end

    def provision!
      return if @esim.route_installed_at? || !@esim.provisioning_authorized?
      @hub.check_peer!(@esim.customer_wg_peer_ip)
      acquire_sim!
      @esim.with_lock do
        return if @esim.route_installed_at? || !@esim.provisioning_authorized?

        card = @client.sim(@esim.telnyx_sim_id)
        unless card["id"] == @esim.telnyx_sim_id && card["sim_card_group_id"] == @esim.sim_card_group_id
          raise WirelessClient::Error, "SIM identity or private group did not match"
        end
        if card["actions_in_progress"] || card.dig("status", "value") == "registering"
          raise WirelessClient::Retryable, "SIM registration is still in progress"
        end

        unless @esim.limit_applied_at?
          @client.set_limit(@esim.telnyx_sim_id, @esim.plan_limit_mb)
          @esim.update!(limit_applied_at: Time.current)
        end
        unless @esim[:lpa_activation_code]
          @esim.update!(lpa_activation_code: @client.activation_code(@esim.telnyx_sim_id))
        end

        if !@esim.activation_requested_at?
          @client.request_status(@esim.telnyx_sim_id, "enabled") unless card.dig("status", "value").in?(%w[enabled enabling])
          @esim.update!(activation_requested_at: Time.current, status: "awaiting_device")
        end
      end
      ProvisionVpsRouteJob.perform_later(@esim.id)
    end

    private

    def acquire_sim!
      should_purchase = @esim.with_lock do
        return if @esim.telnyx_sim_id?
        next false if @esim.purchase_started_at?
        @esim.update!(purchase_started_at: Time.current, status: "purchasing")
        true
      end
      tag = "lightek-esim-#{@esim.request_key}"
      matches = if should_purchase
        @client.purchase(group_id: @esim.sim_card_group_id, tag: tag)
      else
        @client.find_purchase(group_id: @esim.sim_card_group_id, tag: tag)
      end
      if !matches.is_a?(Array) || matches.size > 1
        raise WirelessClient::Error, "Unexpected SIM purchase result; reconcile the purchase tag before continuing"
      end
      raise WirelessClient::Retryable, "Purchased SIM is not visible yet" if matches.empty?

      card = matches.first
      unless card.is_a?(Hash) && UserEsim::UUID.match?(card["id"].to_s) && UserEsim::ICCID.match?(card["iccid"].to_s) &&
          card["sim_card_group_id"] == @esim.sim_card_group_id
        raise WirelessClient::Retryable, "Purchased SIM identity is not confirmed"
      end

      @esim.with_lock do
        if @esim.telnyx_sim_id? && @esim.telnyx_sim_id != card["id"]
          raise WirelessClient::Error, "Purchase tag matches different SIMs"
        end
        @esim.update!(telnyx_sim_id: card["id"], iccid: card["iccid"], status: "provisioning")
      end
    end
  end
end
