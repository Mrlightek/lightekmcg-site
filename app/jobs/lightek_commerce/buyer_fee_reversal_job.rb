# frozen_string_literal: true

module LightekCommerce
  class BuyerFeeReversalJob < ApplicationJob
    queue_as :default
    retry_on ::Stripe::StripeError, wait: :polynomially_longer, attempts: 5

    def perform(order_id = nil)
      if order_id.nil?
        sweep
        return
      end

      order = Order.find_by(id: order_id)
      return unless order

      order.with_lock do
        return unless eligible?(order)

        order.update!(buyer_fee_reversal_requested_at: Time.current) unless order.buyer_fee_reversal_requested_at?
      end

      order.with_lock do
        return unless eligible?(order)
        return if order.buyer_fee_reversal_requested_at < 22.hours.ago

        api_key = DymondBank::StripeCredentials.secret_key.to_s
        raise 'Buyer-fee reversal requires the configured payment key' if api_key.blank?

        reversal = ::Stripe::Transfer.create_reversal(order.merchant_transfer_ref,
          {amount: order.merchant_transfer_amount_cents, metadata: PaymentIdentity.metadata(order)},
          {api_key: api_key, idempotency_key: PaymentIdentity.key(order, 'buyer-fee-refund-v1')})
        unless reversal.id.to_s.start_with?('trr_') && reversal.amount == order.merchant_transfer_amount_cents
          raise 'The provider reversal requires reconciliation'
        end

        order.update!(buyer_fee_reversal_ref: reversal.id)
      end
    end

    private

    def eligible?(order)
      order.status == 'refunded' && order.refunded_cents == order.total_cents &&
        order.buyer_fee_cents.positive? && order.merchant_transfer_ref.present? &&
        order.merchant_transfer_amount_cents == order.buyer_fee_breakdown.fetch('merchant_cents') &&
        order.buyer_fee_reversal_ref.blank?
    end

    def sweep
      Order.where(status: 'refunded', buyer_fee_reversal_ref: nil).where.not(merchant_transfer_ref: nil)
        .where.not(buyer_fee_snapshot: {}).where('buyer_fee_reversal_requested_at IS NULL OR buyer_fee_reversal_requested_at >= ?', 22.hours.ago)
        .order(id: :asc).limit(50).pluck(:id).each { |id| self.class.perform_later(id) }
    end
  end
end
