# frozen_string_literal: true

class ProvisionVpsRouteJob < ApplicationJob
  class WaitingForDevice < StandardError; end

  queue_as :default
  self.enqueue_after_transaction_commit = true
  retry_on WaitingForDevice, wait: 10.minutes, attempts: 145
  retry_on Telnyx::WirelessClient::Retryable, Telnyx::CellularHub::Error, wait: :polynomially_longer, attempts: 9
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    esim = UserEsim.find(id)
    esim.with_lock do
      return unless esim.activation_requested_at?
      return if esim.route_installed_at? || !esim.provisioning_authorized?

      card = Telnyx::WirelessClient.new.sim(esim.telnyx_sim_id)
      unless card["id"] == esim.telnyx_sim_id && card["sim_card_group_id"] == esim.sim_card_group_id
        raise Telnyx::WirelessClient::Error, "SIM no longer belongs to the configured gateway group"
      end
      ip = card["ipv4"]
      raise WaitingForDevice, "Waiting for the first static APN connection" if ip.blank? || card.dig("status", "value") != "enabled"

      network = IPAddr.new(ENV.fetch("TELNYX_SIM_IPV4_CIDR", "10.50.0.0/16"))
      unless UserEsim.host_ipv4?(ip) && network.ipv4? && network.include?(ip) &&
          ![network.to_range.first.to_s, network.to_range.last.to_s].include?(ip)
        raise Telnyx::WirelessClient::Error, "Telnyx SIM IP is outside the configured static subnet"
      end

      # Commit the unique claim before changing the Hub. Retries keep the same address.
      if esim.assigned_private_ip? && esim.assigned_private_ip != ip
        raise Telnyx::WirelessClient::Error, "The SIM address changed after allocation"
      end
      esim.update!(assigned_private_ip: ip, carrier_status: "enabled")
    end

    esim.with_lock do
      return if esim.route_installed_at? || !esim.provisioning_authorized?
      Telnyx::CellularHub.new.install!(esim.assigned_private_ip, esim.customer_wg_peer_ip, esim.routing_table_id)
      esim.update!(route_installed_at: Time.current, status: esim.carrier_status)
    end
  end
end
