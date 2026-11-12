module LightekCommerce
  # Contract terms are frozen at checkout, including for subscription renewals.
  # Only verified, fulfilled sales create transferable earnings. No recruitment
  # event, account registration or downline count produces a financial credit.
  class RevenueSharing
    class Invalid < StandardError; end
    def self.snapshot_for(merchant)
      return [] unless merchant.is_a?(User)
      cursor = merchant
      merchant.account_ancestors.filter_map do |parent|
        basis_points = cursor.upstream_share_bps
        cursor = parent
        {"beneficiary_id" => parent.id, "basis_points" => basis_points} if basis_points.positive?
      end
    end
    def self.quote(order)
      rows = Array(order.revenue_share_snapshot)
      raise Invalid, "Invalid upstream revenue agreement" unless rows.map { |row| row.fetch("beneficiary_id") }.uniq.size == rows.size && rows.sum { |row| row.fetch("basis_points").to_i } <= 10_000 && rows.all? { |row| row.fetch("basis_points").to_i.between?(0, 10_000) }
      rows.map { |row| row.merge("amount_cents" => order.subtotal_cents * row.fetch("basis_points").to_i / 10_000) }
    end
    def self.total_cents(order) = quote(order).sum { |row| row.fetch("amount_cents") }
    def self.record!(order)
      raise Invalid, "Verified payment required" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
      quote(order).each do |row|
        RevenueAllocation.find_or_create_by!(order: order, beneficiary_id: row.fetch("beneficiary_id")) do |allocation|
          allocation.basis_points = row.fetch("basis_points")
          allocation.amount_cents = row.fetch("amount_cents")
          allocation.currency = order.currency
        end
      end
    end
    def self.reverse_for_refunds!(order)
      order.with_lock do
        refunded = 0
        # Stable refund identities keep a processor success followed by a worker
        # failure from reversing the same upstream transfer twice.
        order.refunds.where(status: "succeeded").order(:id).each do |refund|
          refunded += refund.amount_cents
          order.revenue_allocations.each do |allocation|
            target = refunded >= order.total_cents ? allocation.amount_cents : allocation.amount_cents * refunded / order.total_cents
            delta = target - allocation.reversed_cents
            next unless delta.positive?
            if allocation.status == "transferred"
              Stripe.api_key = DymondBank::StripeCredentials.secret_key
              Stripe::Transfer.create_reversal(allocation.transfer_reference, {amount: delta},
                {idempotency_key: PaymentIdentity.key(order, "reverse-share-#{allocation.id}-refund-#{refund.id}")})
            end
            allocation.update!(reversed_cents: target)
          end
        end
      end
    end

    def self.pay!(allocation)
      allocation.order.with_lock do
        allocation.reload
        return allocation unless allocation.status == "pending"
        order = allocation.order
        raise Invalid, "Only fulfilled, nonrefunded sales earn revenue shares" unless order.status == "fulfilled" && order.paid_at? && order.refunded_cents.zero? && !order.refunds.where(status: "pending").exists?
        raise Invalid, "Platform transfers are not enabled" unless ENV["LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED"] == "true"
        # Validate the combined fees, infrastructure reserve and ancestor shares
        # before transferring any part of the original customer payment.
        MerchantPayouts.fee_quote(order)
        if allocation.beneficiary.role == "super_admin" || allocation.amount_cents.zero?
          allocation.update!(status: "retained", settled_at: Time.current)
        else
          beneficiary = allocation.beneficiary
          DymondBank::StripeService.sync_connect_status!(beneficiary)
          raise Invalid, "Recipient must complete Stripe Connect onboarding" unless beneficiary.stripe_connect_ready?
          transfer = DymondBank::StripeService.create_transfer(amount_cents: allocation.amount_cents, currency: allocation.currency,
            destination_account: beneficiary.stripe_connect_account_id, description: "Lightek sale share ##{allocation.id}",
            metadata: PaymentIdentity.metadata(order).merge(revenue_allocation_id: allocation.id.to_s),
            idempotency_key: PaymentIdentity.key(order, "upstream-#{allocation.beneficiary_id}-v1"))
          allocation.update!(status: "transferred", transfer_reference: transfer.id, settled_at: Time.current)
        end
        allocation
      end
    end
  end
end
