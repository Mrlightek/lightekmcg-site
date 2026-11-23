# frozen_string_literal: true

require "uri"

module LightekCommunications
  class InstallationVoice
    class Unavailable < StandardError; end

    def initialize(peer)
      @peer = peer
      raise Unavailable, "Voice requires a connected paid installation." unless peer.order_id && peer.active?
      raise Unavailable, "The installation account is unavailable." unless LightekPeople::LifecycleAccess.active?(peer.merchant)
    end

    def status
      order = VoiceAddOn.find_by(peer: @peer)&.order
      subscription = order&.commerce_subscription
      service = Service.find_by(subscription: subscription) if subscription
      offers = catalog_offers
      state = service&.status || case order&.status
      when "pending_payment" then "pending_payment"
      when "paid", "fulfilled" then "provisioning"
      when "canceled", nil then offers.any? ? "available" : "unavailable"
      else "needs_review"
      end

      {
        status: state,
        billing_status: subscription&.status,
        can_checkout: (state == "pending_payment" || (state == "available" && offers.one?)),
        offers: state == "available" ? offers.map { |offer| summarize_offer(offer) } : [],
        price_cents: state == "pending_payment" ? order.subtotal_cents : offers.one? ? offers.first.price_cents : nil,
        billing_interval: state == "pending_payment" ? order.items.sole.purchase_snapshot.fetch("billing_interval") : offers.one? ? offers.first.billing_interval : nil
      }
    end

    def checkout!(plan: nil)
      destination = return_url
      order = @peer.with_lock do
        add_on = VoiceAddOn.find_or_initialize_by(peer: @peer)
        previous = add_on.order
        if previous&.status == "pending_payment"
          if plan.present? && previous.items.sole.purchase_snapshot["voice_plan"] != plan
            raise Unavailable, "Resume the pending checkout before choosing a different plan."
          end
          next previous
        end
        if previous && previous.status != "canceled"
          raise Unavailable, "This installation already has a Voice order."
        end

        offers = catalog_offers
        product = plan.present? ? offers.find { |offer| offer.slug == plan } : offers.one? ? offers.first : nil
        raise Unavailable, "Choose an available Lightek Voice plan." unless product
        order = LightekCommerce::OrderPlacement.call(site: product.site, customer_email: @peer.merchant.email_address,
          quantities: { product.id => 1 })
        add_on.update!(order: order)
        order
      end

      session = LightekCommerce::StripeCheckout.start!(order: order, success_url: destination, cancel_url: destination)
      { checkout_url: self.class.checkout_url!(session.url) }
    end

    def self.checkout_url!(value)
      uri = URI.parse(value.to_s)
      unless uri.is_a?(URI::HTTPS) && uri.host == "checkout.stripe.com" && uri.port == 443 && !uri.userinfo
        raise Unavailable, "The Voice checkout link is unavailable."
      end
      uri.to_s
    rescue URI::InvalidURIError
      raise Unavailable, "The Voice checkout link is unavailable."
    end

    private

    def summarize_offer(offer)
      { key: offer.slug, name: offer.name, description: offer.short_description,
        price_cents: offer.price_cents, currency: offer.currency, billing_interval: offer.billing_interval }
    end

    def catalog_offers
      origin = URI.parse(LightekReservations::Federation::Issuer.origin)
      site = DymondSite::Site.find_by(host: origin.host)
      return [] if !site || LightekReservations::Federation::Client.config(site).present?

      LightekCommerce::Product.where(site: site, published: true, product_type: "service", billing_interval: %w[month year])
        .where("slug = ? OR slug LIKE ?", "lightek-voice", "lightek-voice-%").where("price_cents > 0")
        .order(:position, :name, :id).select { |product| product.communications_kind == "voice" }
    end

    def return_url
      host = @peer.site.host.to_s
      unless host.match?(/\A[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?)+\z/i)
        raise Unavailable, "The installation address is unavailable."
      end
      "https://#{host}/dashboard/voice"
    end
  end
end
