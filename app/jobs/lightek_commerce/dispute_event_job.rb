# frozen_string_literal: true

module LightekCommerce
  class DisputeEventJob < ApplicationJob
    retry_on ::Stripe::StripeError, wait: :polynomially_longer, attempts: 6
    retry_on LightekPayments::PayoutAccounts::Unavailable, wait: :polynomially_longer, attempts: 6

    def perform(reference)
      options = LightekPayments::PayoutAccounts.options
      dispute = ::Stripe::Dispute.retrieve(reference, options)
      return unless dispute.id == reference

      intent = ProcessorPayment.identifier(dispute.payment_intent)
      return unless intent.to_s.match?(/\Api_[A-Za-z0-9_]+\z/)

      existing = DisputeCase.find_by(processor_reference: reference)
      order = existing&.order || Order.visible.find_by(payment_provider: 'stripe_gift_split', payment_reference: intent) ||
        checkout_order(intent, options) || invoice_order(intent, options)
      return unless order && MerchantLedger.dispute_payment_intent!(order, options) == intent

      order.with_lock do
        current = ::Stripe::Dispute.retrieve(reference, options)
        if current.id == reference && ProcessorPayment.identifier(current.payment_intent) == intent
          DisputeCase.record!(order: order, dispute: current)
          if order.gift_card_purchase?
            card = GiftCard.find_by(purchase_order: order)
            if card
              card.with_lock do
                # Warning closure or a win restores use. A lost or open dispute freezes the remaining balance.
                card.update!(disputed_at: %w[won warning_closed].include?(current.status) ? nil : (card.disputed_at || Time.current))
              end
            end
          end
        end
      end
    rescue MerchantLedger::Invalid
      nil
    end

    private

    def checkout_order(intent, options)
      rows = ::Stripe::Checkout::Session.list({payment_intent: intent, limit: 2}, options).data
      Order.visible.find_by(payment_provider: 'stripe', payment_reference: rows.first.id) if rows.one?
    end

    def invoice_order(intent, options)
      rows = ::Stripe::InvoicePayment.list({payment: {type: 'payment_intent', payment_intent: intent},
        status: 'paid', limit: 2}, options).data
      BillingInvoice.find_by(processor_reference: ProcessorPayment.identifier(rows.first.invoice))&.settlement_order if rows.one?
    end
  end
end
