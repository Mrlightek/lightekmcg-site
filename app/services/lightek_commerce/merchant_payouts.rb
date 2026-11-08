# frozen_string_literal: true
module LightekCommerce
  # Transfers net earned funds from the platform Stripe balance to a merchant's
  # Stripe Connect account. Stripe's payout schedule then governs bank settlement.
  # No bank account numbers are ever stored in Lightek.
  class MerchantPayouts
    class Invalid < StandardError; end

    # USD storefronts reserve processing on the price plus a conservative 25%
    # tax allowance. The platform's cost/margin floor must survive those fees.
    def self.minimum_charge_cents(floor)
      processor = Integer(ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS', '300'))
      platform = Integer(ENV.fetch('LIGHTEK_COMMERCE_PLATFORM_FEE_BPS', '0'))
      fixed = Integer(ENV.fetch('LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS', '30'))
      raise Invalid, 'Fee settings out of range' unless (0..2500).cover?(processor) && (0..2500).cover?(platform) && (0..2000).cover?(fixed)
      fees = processor + platform
      denominator = 100_000_000 - fees * 12_500
      price = ((floor.to_i + fixed) * 100_000_000 + denominator - 1) / denominator
      loop do
        gross = (price * 12_500 + 9999) / 10_000
        reserve = (gross * processor + 9999) / 10_000 + (gross * platform + 9999) / 10_000 + fixed
        return price if price - reserve >= floor.to_i
        price += 1
      end
    end

    def self.fee_quote(order)
      gross = order.total_cents.to_i
      merchandise = order.respond_to?(:subtotal_cents) ? order.subtotal_cents.to_i : gross
      processor_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS", "300"))
      processor_fixed = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS", "30"))
      platform_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PLATFORM_FEE_BPS", "0"))
      raise Invalid, "Fee settings out of range" unless (0..2500).cover?(processor_bps) && (0..2500).cover?(platform_bps) && (0..2000).cover?(processor_fixed)
      processor_reserve = (gross * processor_bps + 9999) / 10_000 + processor_fixed
      platform_fee = (gross * platform_bps + 9999) / 10_000
      reservation = order.respond_to?(:id) ? LightekReservations::Reservation.find_by(order_id: order.id) : nil
      change = order.respond_to?(:id) ? LightekReservations::Change.find_by(order_id: order.id) : nil
      infrastructure = reservation&.server? ? reservation.package_snapshot.fetch('cost_floor_cents', 0).to_i : 0
      if change
        quote = change.quote
        target_floor = quote.dig('target', 'cost_floor_cents').to_i
        old_floor = quote.dig('original', 'cost_floor_cents').to_i
        infrastructure = if quote['renewal']
          target_floor
        else
          difference = [target_floor - old_floor, 0].max
          (difference * quote['unused_seconds'].to_i + quote['term_seconds'].to_i - 1) / [quote['term_seconds'].to_i, 1].max
        end
      end
      {gross_cents: gross, infrastructure_reserve_cents: infrastructure, processor_reserve_cents: processor_reserve,
        platform_fee_cents: platform_fee, net_cents: [merchandise - processor_reserve - platform_fee - infrastructure, 0].max}
    end

    def self.request!(order:, merchant:)
      order.with_lock do
        raise Invalid, "Platform Stripe balance has not been reconciled for transfers" unless ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] == "true"
        raise Invalid, "Order does not belong to your store" unless
          LightekSettings::WebsiteIdentity.sites_for(merchant).where(tenant: merchant).exists?(id: order.site_id)
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
            metadata: PaymentIdentity.metadata(order),
            idempotency_key: PaymentIdentity.key(order, 'merchant-transfer-v1')
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
