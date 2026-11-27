# frozen_string_literal: true

module LightekCommerce
  # A read-only reconciliation of the accepted order and the provider's original
  # charge. Refund totals are displayed separately from original processing cost.
  class MerchantLedger
    class Invalid < StandardError; end

    def self.read(order:, actor:, processor: false)
      raise ActiveRecord::RecordNotFound unless order.site.tenant_type == 'User' && order.site.tenant_id == actor.id &&
        LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: order.site_id)

      record = {
        gross_cents: order.total_cents, merchandise_cents: order.subtotal_cents,
        buyer_checkout_fee_cents: order.buyer_fee_cents.presence, buyer_fee_refunded: order.buyer_fee_cents.positive? && order.status == 'refunded',
        taxes_cents: order.tax_cents, shipping_cents: order.shipping_cents,
        refunded_cents: order.refunded_cents, merchant_transfer_cents: order.merchant_transfer_amount_cents,
        merchant_transfer_ref: order.merchant_transfer_ref, merchant_transfer_at: order.merchant_transfer_completed_at,
        agency_shares_cents: order.revenue_allocations.sum(:amount_cents),
        agency_reversed_cents: order.revenue_allocations.sum(:reversed_cents)
      }
      if record[:buyer_fee_refunded] && order.merchant_transfer_ref.present?
        record[:buyer_fee_reversal_ref] = order.buyer_fee_reversal_ref
        record[:buyer_fee_reversal_pending] = order.buyer_fee_reversal_ref.blank?
      end
      return record if order.payment_provider == 'network'

      quote = MerchantPayouts.fee_quote(order)
      record.merge!(quote.slice(:processor_reserve_cents, :platform_fee_cents, :infrastructure_reserve_cents))
      if processor
        record.merge!(processor_receipt!(order))
        if order.buyer_fee_cents.positive?
          record[:platform_after_processing_cents] = order.buyer_fee_cents - record.fetch(:processor_actual_cents) unless record[:buyer_fee_refunded]
        end
      end
      record
    end

    def self.dispute_payment_intent!(order, options)
      unless order.paid_at? && order.payment_provider.in?(%w[stripe stripe_invoice])
        raise Invalid, 'Verified local Commerce payment is required.'
      end

      verified_intent!(order, options)
    end

    def self.processor_receipt!(order)
      unless order.paid_at? && order.payment_provider.in?(%w[stripe stripe_invoice])
        raise Invalid, 'Verified Commerce payment is required to reconcile processor fees.'
      end

      key = DymondBank::StripeCredentials.secret_key.to_s
      raise Invalid, 'Stripe payment credentials are unavailable.' if key.blank?

      options = {api_key: key}
      intent_id = verified_intent!(order, options)
      intent = hash(::Stripe::PaymentIntent.retrieve({id: intent_id, expand: ['latest_charge.balance_transaction']}, options))
      charge = intent['latest_charge']
      unless intent['id'] == intent_id && intent['status'] == 'succeeded' && intent['currency'] == order.currency &&
          intent['amount_received'] == order.total_cents && charge.is_a?(Hash) && charge['payment_intent'] == intent_id &&
          charge['amount'] == order.total_cents && charge['currency'] == order.currency && charge['paid'] == true
        raise Invalid, 'The processor charge does not match this order.'
      end

      balance = charge['balance_transaction']
      unless balance.is_a?(Hash) && balance['source'] == charge['id'] && balance['currency'] == order.currency &&
          balance['amount'] == order.total_cents && balance['fee'].is_a?(Integer) && balance['fee'] >= 0 &&
          balance['net'] == balance['amount'] - balance['fee'] && balance['status'].in?(%w[pending available])
        raise Invalid, 'A matching processor balance record is not available.'
      end

      {processor_actual_cents: balance['fee'], processor_net_cents: balance['net'],
       processor_funds_state: balance['status'], processor_refunded_cents: charge['amount_refunded'],
       processor_disputed: charge['disputed'] == true}
    rescue ::Stripe::StripeError
      raise Invalid, 'Processor reconciliation is temporarily unavailable.'
    end

    def self.verified_intent!(order, options)
      if order.payment_provider == 'stripe'
        session = hash(::Stripe::Checkout::Session.retrieve(order.payment_reference, options))
        expected = PaymentIdentity.metadata(order).stringify_keys
        unless session['id'] == order.payment_reference && session['payment_status'] == 'paid' &&
            session['currency'] == order.currency && session['amount_total'] == order.total_cents &&
            expected.all? { |key, value| session.fetch('metadata', {})[key] == value }
          raise Invalid, 'The processor checkout does not match this order.'
        end
        return intent_reference!(session['payment_intent']) if session['payment_intent'].present?

        invoice_id = reference(session['invoice'])
      else
        invoice_id = order.payment_reference
      end
      raise Invalid, 'A matching paid invoice is not available.' unless invoice_id.to_s.start_with?('in_') &&
        BillingInvoice.exists?(settlement_order_id: order.id, processor_reference: invoice_id)

      invoice = hash(::Stripe::Invoice.retrieve({id: invoice_id, expand: ['payments']}, options))
      unless invoice['id'] == invoice_id && invoice['status'] == 'paid' && invoice['currency'] == order.currency &&
          invoice['amount_paid'] == order.total_cents
        raise Invalid, 'The processor invoice does not match this order.'
      end
      return intent_reference!(invoice['payment_intent']) if invoice['payment_intent'].present?

      payments = Array(invoice.dig('payments', 'data')).select { |payment| payment['status'] == 'paid' }
      unless payments.one? && !invoice.dig('payments', 'has_more') && payments.first['amount_paid'] == order.total_cents &&
          payments.first.dig('payment', 'type') == 'payment_intent'
        raise Invalid, 'This invoice requires payment reconciliation.'
      end

      intent_reference!(payments.first.dig('payment', 'payment_intent'))
    end

    def self.intent_reference!(value)
      ref = reference(value)
      raise Invalid, 'A matching payment intent is not available.' unless ref.to_s.start_with?('pi_')

      ref
    end

    def self.reference(value) = value.is_a?(Hash) ? value['id'] : value
    def self.hash(value) = value.to_h.deep_stringify_keys
    private_class_method :processor_receipt!, :verified_intent!, :intent_reference!, :hash, :reference
  end
end
