# frozen_string_literal: true
module LightekCommerce
  # Transfers net earned funds from the platform Stripe balance to a merchant's
  # Stripe Connect account. Stripe's payout schedule then governs bank settlement.
  # No bank account numbers are ever stored in Lightek.
  class MerchantPayouts
    class Invalid < StandardError; end

    def self.fee_quote(order)
      gross = order.total_cents.to_i
      merchandise = order.respond_to?(:subtotal_cents) ? order.subtotal_cents.to_i : gross
      processor_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS", "300"))
      processor_fixed = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS", "30"))
      platform_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PLATFORM_FEE_BPS", "0"))
      raise Invalid, "Fee settings out of range" unless (0..2500).cover?(processor_bps) && (0..2500).cover?(platform_bps) && (0..2000).cover?(processor_fixed)
      processor_reserve = (gross * processor_bps + 9999) / 10_000 + processor_fixed
      platform_fee = (gross * platform_bps + 9999) / 10_000
      {gross_cents: gross, processor_reserve_cents: processor_reserve,
        platform_fee_cents: platform_fee, net_cents: [merchandise - processor_reserve - platform_fee, 0].max}
    end

    def self.request!(order:, merchant:)
      order.with_lock do
        raise Invalid, "Platform Stripe balance has not been reconciled for transfers" unless ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] == "true"
        raise Invalid, "Order does not belong to your store" unless
          LightekSettings::WebsiteIdentity.sites_for(merchant).exists?(id: order.site_id)
        return order if order.merchant_transfer_ref.present?
        raise Invalid, "Only fulfilled, nonrefunded orders are eligible" unless order.status == "fulfilled"
        raise Invalid, "Order is not paid" unless order.paid_at.present?
        raise Invalid, "Outstanding refund prevents payout" if order.refunds.where(status: "pending").exists?
        raise Invalid, "Partially refunded order requires manual settlement" if order.refunded_cents.to_i.positive?
        DymondBank::StripeService.sync_connect_status!(merchant)
        raise Invalid, "Complete Stripe Connect onboarding before requesting funds" unless merchant.stripe_connect_ready?
        quote = fee_quote(order)
        raise Invalid, "Net transfer amount is zero" unless quote[:net_cents].positive?
        order.update!(merchant_transfer_requested_at: Time.current, merchant_transfer_error: nil)
        begin
          transfer = DymondBank::StripeService.create_transfer(
            amount_cents: quote.fetch(:net_cents),
            currency: order.currency,
            destination_account: merchant.stripe_connect_account_id,
            description: "Lightek Commerce order ##{order.id}",
            metadata: {lightek_commerce_order_id: order.id.to_s, lightek_site_id: order.site_id.to_s},
            idempotency_key: "lightek-commerce-order-#{order.id}-merchant-transfer-v1"
          )
          order.update!(merchant_transfer_ref: transfer.id,
            merchant_transfer_amount_cents: quote.fetch(:net_cents),
            merchant_transfer_completed_at: Time.current)
        rescue StandardError => e
          order.update!(merchant_transfer_error: "#{e.class}: #{e.message}".slice(0, 1000))
          raise
        end
        order
      end
    end
  end
end
