# frozen_string_literal: true
module LightekMarketplace
  module PaidPurchaseSettlement
    class PaymentNotReady < StandardError; end
    def mark_paid!
      return super unless [88, 89].include?(offer.meta.to_h.dig("lightek_marketplace", "version"))
      with_lock do
        return self if %w[paid provisioning provisioned].include?(status)
        return self if status == "cancelled"
        if amount_cents.to_i.positive?
          invoice&.reload
          unless invoice && invoice.paid? && invoice.billable == customer &&
              invoice.total_cents.to_i == amount_cents.to_i && invoice.amount_remaining_cents.to_i.zero? &&
              invoice.currency.to_s.upcase == currency.to_s.upcase
            raise PaymentNotReady, "The complete order invoice must be paid before delivery"
          end
        end
        if subscription
          subscription.with_lock do
            raise PaymentNotReady, "Subscription customer mismatch" unless subscription.subscriber == customer
            if subscription.canceled?
              update!(error: "Payment received for a canceled subscription; delivery stopped")
              return self
            end
            if subscription.status == "unpaid"
              if offer.trial? && offer.effective_trial_days.positive?
                start = Time.current
                subscription.update!(status: "trialing", trial_ends_at: start + offer.effective_trial_days.days,
                  current_period_start: start, current_period_end: start + offer.effective_trial_days.days)
              else
                subscription.activate!
              end
            end
          end
        end
        super
      end
    end
  end
end
