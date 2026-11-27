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

    def self.fee_quote(order, gross_cents: nil)
      gross = gross_cents || order.total_cents.to_i
      merchandise = order.respond_to?(:subtotal_cents) ? order.subtotal_cents.to_i : gross
      if order.respond_to?(:buyer_fee_breakdown) && (fee = order.buyer_fee_breakdown).present?
        raise Invalid, "Buyer fee settlement does not match the order" unless merchandise == fee.fetch('merchant_cents')

        shipping_margin = order.shipping_quote ? order.shipping_quote.customer_price_cents - order.shipping_quote.platform_price_cents : 0
        return {gross_cents: gross, processor_reserve_cents: fee.fetch('processor_reserve_cents'),
          platform_fee_cents: fee.fetch('network_cents'), infrastructure_reserve_cents: 0,
          upstream_share_cents: 0, net_cents: merchandise + shipping_margin}
      end
      processor_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FEE_BPS", "300"))
      processor_fixed = Integer(ENV.fetch("LIGHTEK_COMMERCE_PROCESSOR_FIXED_CENTS", "30"))
      platform_bps = Integer(ENV.fetch("LIGHTEK_COMMERCE_PLATFORM_FEE_BPS", "0"))
      raise Invalid, "Fee settings out of range" unless (0..2500).cover?(processor_bps) && (0..2500).cover?(platform_bps) && (0..2000).cover?(processor_fixed)
      processor_reserve = (gross * processor_bps + 9999) / 10_000 + processor_fixed
      platform_fee = (gross * platform_bps + 9999) / 10_000
      reservation = order.respond_to?(:id) ? LightekReservations::Reservation.find_by(order_id: order.id) : nil
      change = order.respond_to?(:id) ? LightekReservations::Change.find_by(order_id: order.id) : nil
      hosting = order.respond_to?(:items) ? order.items.first&.purchase_snapshot.to_h.fetch("hosting", {}).to_h : {}
      hosting_reserve = hosting.fetch("platform_charge_cents", hosting.fetch("monthly_cost_ceiling_cents", 0)).to_i
      infrastructure = [reservation&.server? ? reservation.package_snapshot.fetch('cost_floor_cents', 0).to_i : 0, hosting_reserve].max
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
      upstream = order.respond_to?(:revenue_share_snapshot) ? RevenueSharing.total_cents(order) : 0
      shipping_margin = order.respond_to?(:shipping_quote) && order.shipping_quote ? order.shipping_quote.customer_price_cents - order.shipping_quote.platform_price_cents : 0
      available = [merchandise + shipping_margin - processor_reserve - platform_fee - infrastructure, 0].max
      raise Invalid, "Revenue shares exceed the sale's available proceeds" if upstream > available
      {gross_cents: gross, infrastructure_reserve_cents: infrastructure, processor_reserve_cents: processor_reserve,
        platform_fee_cents: platform_fee, upstream_share_cents: upstream, net_cents: available - upstream}
    end

    def self.ineligible_reason(order, quote: nil)
      return "Lightek agency membership fees belong to the platform" if order.purpose == "agency_membership"
      return "Use the creator earnings workspace" if %w[creator_support creator_support_renewal].include?(order.purpose)
      return "Only fulfilled orders are eligible" unless order.status == "fulfilled"
      return "Order is not paid" unless order.paid_at.present?
      return "Refund requires manual settlement" if order.refunded_cents.to_i.positive?
      if order.payment_provider == "network"
        return "Missing network payment reference" if order.network_reference.blank?
        return nil
      end

      checkout_paid = order.payment_provider == "stripe" && order.payment_reference.to_s.start_with?("cs_")
      renewal_paid = order.payment_provider == "stripe_invoice" && order.payment_reference.present? &&
        BillingInvoice.exists?(settlement_order_id: order.id, processor_reference: order.payment_reference)
      return "Only verified store payments may fund earnings releases" unless checkout_paid || renewal_paid
      return "Net transfer amount is zero" unless (quote || fee_quote(order))[:net_cents].positive?
    end

    def self.request!(order:, merchant:)
      if order.payment_provider == "network"
        raise Invalid, "Order does not belong to your store" unless order.site.tenant == merchant
        return order if order.merchant_transfer_ref.present?
        reason = ineligible_reason(order)
        raise Invalid, reason if reason
        raise Invalid, "Outstanding refund prevents payout" if order.refunds.where(status: "pending").exists?
        NetworkCheckout.action!(order: order, action: "payout")
        raise Invalid, "Network release receipt is not available yet. Retry to reconcile." unless order.reload.merchant_transfer_ref.present?
        return order
      end

      buyer_fee_order = order.buyer_fee_breakdown.present?
      reserve_buyer_fee_release!(order, merchant) if buyer_fee_order

      transfer_error = nil
      order.with_lock do
        authorize_release!(order, merchant)
        return order if order.merchant_transfer_ref.present?
        DymondBank::StripeService.sync_connect_status!(merchant)
        raise Invalid, "Complete payout account verification before requesting funds" unless merchant.stripe_connect_ready?
        RevenueSharing.record!(order)
        quote = fee_quote(order)
        raise Invalid, "Net transfer amount is zero" unless quote[:net_cents].positive?
        if buyer_fee_order && order.buyer_fee_transfer_destination != merchant.stripe_connect_account_id
          raise Invalid, 'The payout account changed. Reconcile the original earnings release.'
        end
        order.update!(merchant_transfer_requested_at: Time.current, merchant_transfer_error: nil) unless buyer_fee_order
        begin
          transfer = DymondBank::StripeService.create_transfer(
            amount_cents: quote.fetch(:net_cents),
            currency: order.currency,
            destination_account: merchant.stripe_connect_account_id,
            description: "Lightek Commerce order ##{order.id}",
            metadata: PaymentIdentity.metadata(order),
            idempotency_key: PaymentIdentity.key(order, 'merchant-transfer-v1')
          )
        rescue DymondBank::StripeService::StripeError, DymondBank::StripeService::ConfigurationError => error
          order.update!(merchant_transfer_error: error.message.slice(0, 1000))
          transfer_error = error
        else
          order.update!(merchant_transfer_ref: transfer.id,
            merchant_transfer_amount_cents: quote.fetch(:net_cents),
            merchant_transfer_completed_at: Time.current)
        end
      end
      raise transfer_error if transfer_error
      order
    end

    def self.reserve_buyer_fee_release!(order, merchant)
      order.with_lock do
        authorize_release!(order, merchant)
        return if order.merchant_transfer_ref.present?

        merchant.reload
        if order.merchant_transfer_requested_at
          if order.merchant_transfer_requested_at < 22.hours.ago || order.buyer_fee_transfer_destination != merchant.stripe_connect_account_id
            raise Invalid, 'Reconcile the previous transfer attempt before releasing these earnings.'
          end
        else
          raise Invalid, 'Complete payout account setup before requesting funds.' if merchant.stripe_connect_account_id.blank?

          order.update!(merchant_transfer_requested_at: Time.current,
            buyer_fee_transfer_destination: merchant.stripe_connect_account_id, merchant_transfer_error: nil)
        end
      end
    end

    def self.authorize_release!(order, merchant)
      raise Invalid, "Order does not belong to your store" unless
        LightekSettings::WebsiteIdentity.sites_for(merchant).where(tenant: merchant).exists?(id: order.site_id)
      return if order.merchant_transfer_ref.present?

      reason = ineligible_reason(order)
      raise Invalid, reason if reason
      raise Invalid, "Platform funds have not been reconciled for earnings release" unless ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] == "true"
      raise Invalid, "Outstanding refund prevents payout" if order.refunds.where(status: "pending").exists?
    end
    private_class_method :authorize_release!, :reserve_buyer_fee_release!
  end
end
