# frozen_string_literal: true

module LightekSales
  class CommissionPayoutReconciliationJob < ApplicationJob
    retry_on DymondBank::WorkforcePayouts::ProviderError, wait: :polynomially_longer, attempts: 5

    def perform(payout_id, poll = 0)
      payout = CommissionPayout.find_by(id: payout_id)
      return unless payout&.state.in?(%w[confirming processing])

      CommissionDisbursements.new(actor: payout.owner, site: payout.referral.partner.site).refresh!(payout: payout)
      if payout.reload.state == 'processing' && poll < 8
        self.class.set(wait: [15.minutes * (2**poll), 12.hours].min).perform_later(payout_id, poll + 1)
      end
    rescue ActiveRecord::RecordNotFound, CommissionDisbursements::Invalid, DymondBank::WorkforcePayouts::Unavailable => error
      Rails.logger.warn("Sales commission reconciliation requires review for payout #{payout_id}: #{error.class}")
    end
  end
end
