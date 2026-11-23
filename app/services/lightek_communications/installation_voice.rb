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
      add_on = VoiceAddOn.find_by(peer: @peer)
      order = add_on&.order
      subscription = order&.commerce_subscription
      service = Service.find_by(subscription: subscription) if subscription
      offers = catalog_offers
      number_request = order&.items&.sole&.purchase_snapshot.to_h["voice_number_request"]
      state = service&.status || case order&.status
      when "pending_payment" then "pending_payment"
      when "paid", "fulfilled" then "provisioning"
      when "canceled", nil then offers.any? ? "available" : "unavailable"
      else "needs_review"
      end

      {
        status: state,
        billing_status: subscription&.status,
        fulfillment_status: add_on&.fulfillment_status,
        phone_number: assigned_number(service, add_on),
        device_settings: service&.status == "in_service" && LightekVault::Secret.exists?(slug: ManagedVoiceTrunk.slug(add_on)),
        number_request: number_request&.slice("option", "area_code")&.merge(
          "last_four" => number_request["phone_number"]&.last(4)),
        can_checkout: state.in?(%w[pending_payment available]),
        offers: state == "available" ? offers.map { |offer| summarize_offer(offer) } : [],
        price_cents: state == "pending_payment" ? order.subtotal_cents : offers.one? ? offers.first.price_cents : nil,
        billing_interval: state == "pending_payment" ? order.items.sole.purchase_snapshot.fetch("billing_interval") : offers.one? ? offers.first.billing_interval : nil
      }
    end

    def checkout!(plan: nil, number_request: {}, voice_setup: {})
      destination = return_url
      order = @peer.with_lock do
        add_on = VoiceAddOn.find_or_initialize_by(peer: @peer)
        previous = add_on.order
        if previous&.status == "pending_payment"
          if plan.present? && previous.items.sole.purchase_snapshot["voice_plan"] != plan
            raise Unavailable, "Resume the pending checkout before choosing a different plan."
          end
          if number_request.values.any?(&:present?) &&
              requested_number!(number_request) != previous.items.sole.purchase_snapshot["voice_number_request"]
            raise Unavailable, "Resume your pending checkout to keep its original number request."
          end
          next previous
        end
        if previous && previous.status != "canceled"
          raise Unavailable, "This installation already has a Voice order."
        end

        offers = catalog_offers
        product = plan.present? ? offers.find { |offer| offer.slug == plan } : offers.one? ? offers.first : nil
        raise Unavailable, "Choose an available Lightek Voice plan." unless product
        selection = requested_number!(number_request)
        order = LightekCommerce::OrderPlacement.call(site: product.site, customer_email: @peer.merchant.email_address,
          quantities: { product.id => 1 })
        item = order.items.sole
        item.update!(purchase_snapshot: item.purchase_snapshot.merge("voice_number_request" => selection))
        slug = VoiceSetup.store!(peer: @peer, order: order, selection: selection, fields: voice_setup)
        add_on.update!(order: order, setup_secret_slug: slug, fulfillment_status: nil)
        order
      end

      session = LightekCommerce::StripeCheckout.start!(order: order, success_url: destination, cancel_url: destination)
      { checkout_url: self.class.checkout_url!(session.url) }
    end

    def device!
      add_on = VoiceAddOn.find_by(peer: @peer)
      subscription = add_on&.order&.commerce_subscription
      service = Service.find_by(subscription: subscription, kind: "voice", status: "in_service") if subscription
      unless service && add_on.fulfillment_status == "carrier_ready" && Fulfillment.billing_receipt(subscription)
        raise Unavailable, "Phone settings are unavailable until your line is active."
      end

      details = ManagedVoiceTrunk.checkout!(add_on)
      { host: ENV.fetch("LIGHTEK_VOICE_SIP_HOST"), port: 5061, transport: "TLS", media_encryption: "SRTP",
        username: AsteriskVoice.device_name(add_on.order_id), password: details.fetch("device_password") }
    rescue ActiveRecord::RecordNotFound, KeyError, LightekVault::MasterKey::ConfigurationError,
           LightekVault::Service::AccessDenied, LightekVault::Crypto::DecryptionError
      raise Unavailable, "Phone settings are unavailable for this line."
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

    def assigned_number(service, add_on)
      return unless service && add_on.fulfillment_status == "carrier_ready"

      operation = VoiceCarrierOperation.find_by(service: service, operation: CarrierFulfillment::NUMBER_ACTIONS, state: "confirmed")
      "+1#{operation.did}" if operation
    end

    def requested_number!(fields)
      case fields["option"]
      when "new"
        area_code = fields["area_code"].to_s.strip
        raise Unavailable, "Enter a three-digit US area code for your new number." unless area_code.match?(/\A[2-9][0-9]{2}\z/)

        { "option" => "new", "area_code" => area_code }
      when "port"
        digits = fields["phone_number"].to_s.delete(" +().-")
        phone_number = "+1#{digits.delete_prefix('1')}"
        if fields["phone_number"].to_s.length > 30 || !VoipMs::NANP_NUMBER.match?(phone_number)
          raise Unavailable, "Enter the US business landline number you want to transfer."
        end

        { "option" => "port", "phone_number" => phone_number }
      else
        raise Unavailable, "Choose a new phone number or keep your existing number."
      end
    end

    def summarize_offer(offer)
      { key: offer.slug, name: offer.name, description: offer.short_description,
        price_cents: offer.price_cents, currency: offer.currency, billing_interval: offer.billing_interval }
    end

    def catalog_offers
      return [] unless VoiceSetup.route(@peer) && VoipMs.configured?

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
