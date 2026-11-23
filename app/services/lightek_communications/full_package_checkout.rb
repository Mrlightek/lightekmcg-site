# frozen_string_literal: true

require "uri"

module LightekCommunications
  class FullPackageCheckout
    class Invalid < StandardError; end

    def self.offer(product)
      return unless product.full_communications_package? && product.published? &&
        product.billing_interval == "month" && product.currency == "usd" && product.subscription_plan_id.present?
      return unless product.site.tenant&.role == "super_admin" && product.site.host == URI.parse(LightekReservations::Federation::Issuer.origin).host
      return unless ManagedVoiceTrunk.destination && VoipMs.configured?

      policy = CellularBundle.config
      plans = policy["signup_plans"]
      tunnels = policy["signup_tunnels"]
      return unless plans.is_a?(Hash) && tunnels.is_a?(Hash) && tunnels.any?

      CellularBundle.configured_offer(product, plan: plans[product.slug], policy: policy)
    end

    def self.eligible?(buyer)
      !LightekCommerce::Installations.scope_for(buyer).where(status: %w[pending_payment paid fulfilled]).exists?
    end

    def self.reserve!(actor:, product:, checkout_key:, number_request:, fields:)
      raise Invalid, "Invalid checkout key" unless UserEsim::UUID.match?(checkout_key.to_s)
      actor.with_lock do
        orders = LightekCommerce::Installations.scope_for(actor)
        prior = orders.find_by(client_checkout_key: checkout_key.downcase)
        return prior if prior && prior.items.sole.product_id == product.id && FullPackage.exists?(order_id: prior.id)

        raise Invalid, "Use your existing CMS workspace to add phone and mobile data." unless eligible?(actor)
        details = offer(product) || raise(Invalid, "This package is temporarily unavailable.")
        selection = InstallationVoice.requested_number!(number_request)

        # Serialize claims against the pool across customers and application processes.
        product.site.with_lock do
          # Only an unpaid, canceled checkout can release an unused tunnel.
          expired = LightekCommerce::Order.where(site_id: product.site_id, status: "canceled", paid_at: nil)
          FullPackage.where(order_id: expired.select(:id), tunnel_ready_at: nil).delete_all
          pool = CellularBundle.config["signup_tunnels"]
          used = FullPackage.pluck(:peer_ip) + UserEsim.pluck(:customer_wg_peer_ip) + VoiceAddOn.where.not(cellular_peer_ip: nil).pluck(:cellular_peer_ip)
          tunnel = pool.find do |ip, slug|
            UserEsim.host_ipv4?(ip) && slug.is_a?(String) && slug.present? && !used.include?(ip)
          end if pool.is_a?(Hash)
          raise Invalid, "There is no available mobile network capacity." unless tunnel

          Telnyx::CellularHub.new.check_peer!(tunnel.first)
          order = LightekCommerce::OrderPlacement.call(site: product.site, customer_email: actor.email_address,
            quantities: { product.id => 1 }, buyer: actor, full_package_offer: details)
          order.update!(client_checkout_key: checkout_key.downcase)
          item = order.items.sole
          item.update!(purchase_snapshot: item.purchase_snapshot.merge("voice_number_request" => selection))
          secret = VoiceSetup.store!(buyer: actor, order: order, selection: selection, fields: fields)
          FullPackage.create!(order: order, buyer: actor, peer_ip: tunnel.first, tunnel_secret_slug: tunnel.last,
            voice_secret_slug: secret, group_id: details.fetch("group_id"), request_key: SecureRandom.uuid)
          order
        end
      end
    rescue Telnyx::CellularHub::Error
      raise Invalid, "Mobile network setup is temporarily unavailable."
    end
  end
end
