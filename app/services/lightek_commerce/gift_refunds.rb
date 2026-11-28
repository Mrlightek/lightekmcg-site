# frozen_string_literal: true

module LightekCommerce
  class GiftRefunds
    FLAG = 'lightek_gift_refund'

    def self.issue!(order:, amount_cents:)
      order.with_lock do
        return order.refunds.find_by!(status: 'succeeded') if order.status == 'refunded'
        unless %w[paid fulfilled].include?(order.status) && amount_cents == order.total_cents && order.refunded_cents.zero?
          raise Refunds::Invalid, 'Gift card purchases and payments require a full refund.'
        end
        if order.merchant_transfer_requested_at? && !order.merchant_transfer_ref?
          raise Refunds::Invalid, 'Reconcile the pending merchant transfer before refunding.'
        end

        record = order.refunds.find_by(status: 'pending')
        unless record
          block_funding_card!(order) if order.gift_card_purchase?
          attempt = order.refunds.count + 1
          order.refunds.create!(amount_cents: amount_cents, gift_restore_cents: order.gift_applied,
            idempotency_key: PaymentIdentity.key(order, "gift-refund-#{attempt}"))
        end
      end

      reconcile!(order)
    rescue ::Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable, MerchantLedger::Invalid
      raise Refunds::Invalid, 'Stripe has yet to confirm this refund. Retry the existing refund to reconcile it.'
    end

    def self.reconcile!(order)
      order.with_lock do
        record = order.refunds.find_by(status: 'pending')
        return order.refunds.find_by!(status: 'succeeded') unless record
        cash = record.amount_cents - record.gift_restore_cents
        return complete!(order, record) if cash.zero?

        options = GiftCheckout.options(order)
        if record.processor_ref.present?
          receipt = ::Stripe::Refund.retrieve(record.processor_ref, options)
        else
          raise Refunds::Invalid, 'The original refund needs provider reconciliation.' if record.created_at < 22.hours.ago

          receipt = ::Stripe::Refund.create({payment_intent: payment_intent(order, options), amount: cash,
            reason: 'requested_by_customer', metadata: metadata(order, record)},
            options.merge(idempotency_key: record.idempotency_key))
        end
        accept_locked!(order, record, receipt, options)
      end
    end

    def self.process_event!(receipt)
      fields = receipt.metadata.to_h.stringify_keys
      order = Order.find_by(id: fields['lightek_commerce_order_id'], payment_namespace: fields['lightek_host_key'])
      return unless order && (order.gift_card_purchase? || order.gift_card_redemption?) && order.site_id.to_s == fields['lightek_site_id']

      order.with_lock do
        record = order.refunds.find_by(id: fields['lightek_gift_refund_id'])
        return unless record&.status == 'pending'

        accept_locked!(order, record, receipt, GiftCheckout.options(order))
      end
    end

    def self.accept_locked!(order, record, receipt, options)
      receipt_fields = receipt.metadata.to_h.stringify_keys
      unless receipt.id.to_s.start_with?('re_') && (record.processor_ref.blank? || record.processor_ref == receipt.id) &&
          receipt.amount == record.amount_cents - record.gift_restore_cents && receipt.currency == order.currency &&
          receipt.payment_intent == payment_intent(order, options) &&
          metadata(order, record).stringify_keys.all? { |key, value| receipt_fields[key] == value }
        raise Refunds::Invalid, 'The Stripe refund does not match the order.'
      end

      record.update!(processor_ref: receipt.id)
      case receipt.status
      when 'succeeded'
        complete!(order, record)
      when 'failed', 'canceled'
        record.update!(status: 'failed')
        if order.gift_card_purchase?
          card = GiftCard.find_by!(purchase_order: order)
          card.with_lock { card.update!(blocked_at: nil) }
        end
      end
      record
    end

    def self.complete!(order, record)
      if order.gift_card_purchase?
        card = GiftCard.find_by!(purchase_order: order)
        card.with_lock do
          card.update!(available_cents: 0, revoked_at: Time.current)
        end
      else
        redemption = GiftRedemption.find_by!(order: order, state: 'captured')
        reference = PaymentIdentity.key(order, 'gift-tax-refund')
        tax = ::Stripe::Tax::Transaction.create_reversal({mode: 'full', original_transaction: redemption.tax_transaction,
          reference: reference}, GiftCheckout.options(order, 'gift-tax-refund'))
        unless tax.id.to_s.start_with?('tax_') && tax.reference == reference && tax.currency == order.currency
          raise Refunds::Invalid, 'Stripe has yet to confirm the tax reversal.'
        end

        card = redemption.gift_card
        card.with_lock do
          card.update!(available_cents: card.available_cents + redemption.amount_cents)
          redemption.update!(state: 'refunded', tax_reversal: tax.id)
        end
      end
      record.update!(status: 'succeeded')
      order.update!(status: 'refunded', refunded_cents: record.amount_cents)
      record
    end

    def self.block_funding_card!(order)
      card = GiftCard.find_by!(purchase_order: order)
      card.with_lock do
        if !card.usable? || card.available_cents != card.face_cents
          raise Refunds::Invalid, 'A gift card with applied funds cannot be refunded as a purchase.'
        end

        card.update!(blocked_at: Time.current)
      end
    end

    def self.payment_intent(order, options)
      return order.payment_reference if order.gift_card_redemption?

      MerchantLedger.dispute_payment_intent!(order, options)
    end

    def self.metadata(order, record)
      PaymentIdentity.metadata(order).merge(FLAG => '1', 'lightek_gift_refund_id' => record.id.to_s)
    end

    private_class_method :accept_locked!, :complete!, :block_funding_card!, :payment_intent, :metadata
  end
end
