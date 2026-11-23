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
      offer = catalog_offer
      state = service&.status || case order&.status
      when "pending_payment" then "pending_payment"
      when "paid", "fulfilled" then "provisioning"
      when "canceled", nil then offer ? "available" : "unavailable"
      else "needs_review"
      end

      {
        status: state,
        billing_status: subscription&.status,
        can_checkout: (state == "pending_payment" || state == "available"),
        price_cents: state == "pending_payment" ? order.subtotal_cents : offer&.price_cents,
        currency: state == "pending_payment" ? order.currency : offer&.currency,
        billing_interval: state == "pending_payment" ? order.items.sole.purchase_snapshot.fetch("billing_interval") : offer&.billing_interval
      }
    end

    def checkout!
      destination = return_url
      order = @peer.with_lock do
        add_on = VoiceAddOn.find_or_initialize_by(peer: @peer)
        previous = add_on.order
        next previous if previous&.status == "pending_payment"
        if previous && previous.status != "canceled"
          raise Unavailable, "This installation already has a Voice order."
        end

        product = catalog_offer || raise(Unavailable, "Lightek Voice is not available for signup yet.")
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

    def catalog_offer
      origin = URI.parse(LightekReservations::Federation::Issuer.origin)
      site = DymondSite::Site.find_by(host: origin.host)
      return if !site || LightekReservations::Federation::Client.config(site).present?

      product = LightekCommerce::Product.find_by(site: site, slug: "lightek-voice", published: true)
      product if product&.communications_kind == "voice" && product.price_cents.positive?
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
