# frozen_string_literal: true

module Studio
  module Advertising
    class SettlePaymentJob < ApplicationJob
      queue_as :default

      def perform(id)
        payment = Payment.find_by(id: id)
        return unless payment

        if payment.charge_reference
          DymondBank::BroadcastAdvertising::Settlement.reconcile_charge!(payment)
        else
          DymondBank::BroadcastAdvertising::Funding.reconcile!(payment)
        end
      rescue DymondBank::BroadcastAdvertising::Funding::PaymentChanged => error
        payment&.update!(state: "held", reconcile_after: nil)
        Rails.logger.warn("[BroadcastAds] payment=#{id} reconciliation=#{error.class}")
      rescue DymondBank::BroadcastAdvertising::Funding::Unavailable => error
        payment&.update!(reconcile_after: 5.minutes.from_now)
        Rails.logger.warn("[BroadcastAds] payment=#{id} reconciliation=#{error.class}")
      end
    end
  end
end
