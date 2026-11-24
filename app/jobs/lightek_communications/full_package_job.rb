# frozen_string_literal: true

module LightekCommunications
  class FullPackageJob < ApplicationJob
    class NotReady < StandardError; end

    queue_as :default
    self.enqueue_after_transaction_commit = true
    retry_on NotReady, Telnyx::CellularHub::Error, Gatekeeper::Fleet::Transport::RemoteFailure,
      wait: :polynomially_longer, attempts: 8

    def self.enqueue!(order)
      perform_later(order.id) if FullPackage.exists?(order_id: order.id)
    end

    def perform(order_id)
      package = FullPackage.find_by(order_id: order_id)
      return unless package
      order = package.order
      return unless order.paid_at? && %w[paid fulfilled].include?(order.status)

      package.with_lock do
        order.reload
        return unless order.paid_at? && %w[paid fulfilled].include?(order.status)
        peer = LightekReservations::Peer.find_by(order_id: order.id)
        unless LightekCommerce::Installations.ready?(order) && peer&.active? && peer.merchant_id == package.buyer_id &&
            order.commerce_subscription && Fulfillment.billing_receipt(order.commerce_subscription)
          raise NotReady, "The paid CMS workspace is still being prepared."
        end

        unless package.tunnel_ready_at?
          install_tunnel!(package, order)
          package.update!(tunnel_ready_at: Time.current)
        end
        add_on = VoiceAddOn.find_or_initialize_by(peer: peer)
        raise NotReady, "The workspace already has a different phone plan." if add_on.persisted? && add_on.order_id != order.id

        if add_on.new_record?
          add_on.update!(order: order, setup_secret_slug: package.voice_secret_slug, cellular_request_key: package.request_key,
            cellular_peer_ip: package.peer_ip, cellular_group_id: package.group_id)
        end
      end
      VoiceProvisioningJob.enqueue_paid!(order)
      CellularBundleJob.enqueue_paid!(order)
    end

    private

    def install_tunnel!(package, order)
      node = ProvisioningRequest.find_by(id: order.provisioning_request_id)&.gatekeeper_node
      unless node && !node.local?
        raise NotReady, "The package requires a dedicated, managed CMS server."
      end

      profile = LightekVault::Service.checkout!(slug: package.tunnel_secret_slug, consumer: self.class.name,
        purpose: "cellular_tunnel", requested_by: "full-package:#{order.id}")
      unless profile["peer_ip"] == package.peer_ip
        raise NotReady, "The allocated cellular peer does not match the tunnel profile."
      end

      receipt = Gatekeeper::Fleet::Transport.run!(node: node, domain: LightekCommerce::Installations.hostname(order),
        operation_id: nil, requested_by: "full-package:#{order.id}", script_name: "install_cellular_tunnel.py",
        payload: profile.slice("peer_ip", "private_key", "hub_public_key", "endpoint").merge(
          "sim_cidr" => ENV.fetch("TELNYX_SIM_IPV4_CIDR", "10.50.0.0/16")))
      unless receipt["status"] == "ready" && receipt["peer_ip"] == package.peer_ip
        raise NotReady, "The CMS server has not verified its cellular tunnel."
      end
      Telnyx::CellularHub.new.check_connected_peer!(package.peer_ip)
    ensure
      profile&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end
  end
end
