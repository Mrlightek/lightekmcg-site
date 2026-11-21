# frozen_string_literal: true

module DymondBank
  module BroadcastAdvertising
    class Funding
      class Unavailable < StandardError; end
      class PaymentChanged < Unavailable; end
      CHECKOUT_EVENTS = %w[checkout.session.completed checkout.session.expired].freeze
      CHARGE_EVENTS = %w[charge.refunded charge.dispute.created charge.dispute.closed].freeze
      MARKER = "lightek_broadcast_ad_key"

      def self.options = LightekPayments::PayoutAccounts.options
      def self.metadata(payment) = { MARKER => payment.public_key }
      def self.key(payment, action) = "lightek-ad-#{payment.public_key}-#{action}"

      def self.checkout_event?(event)
        CHECKOUT_EVENTS.include?(event.type) && !event.data.object.metadata.to_h.transform_keys(&:to_s)[MARKER].to_s.empty?
      end

      def self.process!(event)
        object = event.data.object
        if checkout_event?(event)
          payment = Studio::Advertising::Payment.find_by(public_key: object.metadata.to_h.stringify_keys[MARKER])
          Studio::Advertising::SettlePaymentJob.perform_later(payment.id) if payment && payment.checkout_reference == object.id
        elsif CHARGE_EVENTS.include?(event.type)
          reference = event.type == "charge.refunded" ? object.id : object.charge
          payment = Studio::Advertising::Payment.find_by(charge_reference: reference) if reference.present?
          Studio::Advertising::SettlePaymentJob.perform_later(payment.id) if payment
        end
      end

      def self.checkout_key(payment) = key(payment, "checkout-#{payment.checkout_attempt}")

      def self.checkout_amount(payment)
        payment.checkout_amount_cents || LightekCommerce::MerchantPayouts.minimum_charge_cents(payment.amount_cents)
      end

      def self.checkout!(payment, return_url:)
        # Persist the request identity before calling the processor so a lost
        # response resumes the same checkout instead of opening a second hold.
        payment.with_lock do
          raise Unavailable, "This ad is outside its payment window." unless payment.state == "unfunded" && payment.can_book_payment?
          if payment.checkout_requested_at && !payment.checkout_reference && payment.checkout_requested_at < 61.minutes.ago
            payment.update!(checkout_requested_at: nil, checkout_attempt: payment.checkout_attempt + 1)
          end
          payment.update!(checkout_requested_at: payment.checkout_requested_at || Time.current,
            checkout_amount_cents: checkout_amount(payment), reconcile_after: 1.minute.from_now)
        end

        payment.with_lock do
          raise Unavailable, "This ad is outside its payment window." unless payment.state == "unfunded" && payment.can_book_payment?
          opts = options
          session = if payment.checkout_reference
            Stripe::Checkout::Session.retrieve(payment.checkout_reference, opts)
          else
            raise Unavailable, "This payment attempt has expired." if payment.checkout_requested_at < 20.minutes.ago

            # Cover processing on top of the agreed allocation. The net
            # charge is verified again before any recipient transfer.
            Stripe::Checkout::Session.create({
              mode: "payment", payment_method_types: ["card"], metadata: metadata(payment),
              payment_intent_data: { capture_method: "manual", metadata: metadata(payment) },
              line_items: [{ price_data: { currency: "usd", unit_amount: payment.checkout_amount_cents, product_data: { name: "Broadcast ad placement" } }, quantity: 1 }],
              success_url: return_url, cancel_url: return_url,
              expires_at: (payment.checkout_requested_at + 60.minutes).to_i
            }, opts.merge(idempotency_key: checkout_key(payment)))
          end
          payment.update!(checkout_reference: session.id) if payment.checkout_reference.nil?
          url = URI.parse(session.url.to_s)
          unless session.status == "open" && url.is_a?(URI::HTTPS) && url.host == "checkout.stripe.com" &&
              url.port == 443 && !url.userinfo
            raise Unavailable, "The secure payment page is no longer open."
          end
          url.to_s
        end
      rescue Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable, URI::InvalidURIError
        raise Unavailable, "Secure payment is temporarily unavailable. Please retry."
      end

      def self.reconcile!(payment)
        payment.with_lock do
          next unless payment.checkout_reference

          opts = options
          session = Stripe::Checkout::Session.retrieve(payment.checkout_reference, opts)
          unless session.metadata.to_h.stringify_keys[MARKER] == payment.public_key && session.currency == "usd" &&
              session.mode == "payment" && session.amount_total == payment.checkout_amount_cents
            raise PaymentChanged, "The checkout does not match this placement."
          end
          if session.status == "expired"
            if payment.can_book_payment?
              payment.update!(checkout_reference: nil, checkout_requested_at: nil,
                checkout_attempt: payment.checkout_attempt + 1, reconcile_after: nil)
            else
              payment.update!(state: "void", reconcile_after: nil)
            end
            next
          end
          unless session.status == "complete" && session.payment_intent.present?
            payment.update!(reconcile_after: 2.minutes.from_now)
            next
          end

          intent = load_intent!(payment, session.payment_intent)
          raise PaymentChanged, "Authorized amount changed." unless intent.amount == session.amount_total
          if intent.status == "requires_capture"
            authorize_or_reconcile!(payment, intent, opts)
          elsif intent.status == "succeeded"
            record_capture!(payment, intent)
          elsif intent.status == "canceled"
            payment.update!(state: "void", reconcile_after: nil)
          else
            payment.update!(reconcile_after: 2.minutes.from_now)
          end
        end
      rescue Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable
        raise Unavailable, "Payment verification is temporarily unavailable."
      end

      def self.load_intent!(payment, reference = payment.intent_reference)
        intent = Stripe::PaymentIntent.retrieve({ id: reference, expand: ["latest_charge.balance_transaction"] }, options)
        unless intent.id == reference && intent.metadata.to_h.stringify_keys[MARKER] == payment.public_key && intent.currency == "usd" &&
            intent.capture_method == "manual" && (!payment.intent_reference || payment.intent_reference == intent.id)
          raise PaymentChanged, "Payment does not match this ad placement."
        end
        intent
      end

      def self.authorize_or_reconcile!(payment, intent, opts)
        charge = intent.latest_charge
        deadline = charge.try(:payment_method_details)&.card&.try(:capture_before)
        raise PaymentChanged, "Card authorization could not be verified." unless deadline && charge.payment_intent == intent.id && intent.amount_capturable == intent.amount

        if payment.placement.delivered_at?
          Stripe::PaymentIntent.capture(intent.id, {}, opts.merge(idempotency_key: key(payment, "capture")))
          record_capture!(payment, load_intent!(payment, intent.id))
        elsif payment.placement.finished_without_delivery?
          Stripe::PaymentIntent.cancel(intent.id, {}, opts.merge(idempotency_key: key(payment, "void")))
          payment.update!(state: "void", intent_reference: intent.id, reconcile_after: nil)
        else
          payment.update!(state: "authorized", intent_reference: intent.id, authorized_until: Time.at(deadline), reconcile_after: 2.minutes.from_now)
        end
      end

      def self.record_capture!(payment, intent)
        charge = intent.latest_charge
        unless payment.placement.delivered_at? && charge.respond_to?(:captured) && charge.payment_intent == intent.id &&
            intent.status == "succeeded" && intent.amount_received == charge.amount && charge.paid && charge.captured &&
            charge.currency == "usd" && charge.amount >= payment.amount_cents &&
            (payment.charge_reference.nil? || payment.charge_reference == charge.id)
          raise PaymentChanged, "Captured funds do not match a delivered ad."
        end
        held = charge.disputed || charge.amount_refunded.to_i.positive?
        payment.update!(state: held ? "held" : "captured", intent_reference: intent.id, charge_reference: charge.id,
          captured_at: payment.captured_at || Time.current, reconcile_after: nil)
      end
      private_class_method :authorize_or_reconcile!, :record_capture!
    end
  end
end
