# frozen_string_literal: true

module DymondBank
  module BroadcastAdvertising
    class Settlement
      def self.release!(payout, actor:)
        raise Funding::Unavailable, "This payout belongs to another account." unless payout.recipient_id == actor.id
        raise Funding::Unavailable, "Complete payout verification first." unless LightekPayments::PayoutAccounts.status(actor)[:state] == "ready"

        payout.payment.with_lock do
          payout.reload
          return payout if payout.transfer_reference
          payable_charge!(payout.payment)
          if payout.destination && payout.destination != actor.reload.stripe_connect_account_id
            raise Funding::Unavailable, "The payout account changed. Contact support to reconcile this transfer."
          end
          payout.update!(destination: actor.stripe_connect_account_id, requested_at: payout.requested_at || Time.current)
        end

        payout.payment.with_lock do
          payout.reload
          return payout if payout.transfer_reference
          payment = payout.payment
          charge = payable_charge!(payment)
          # Provider idempotency keys have a retention window. An older
          # uncertain request must be reconciled before money can move again.
          raise Funding::Unavailable, "An older transfer request needs reconciliation." if payout.requested_at < 23.hours.ago

          transfer = Stripe::Transfer.create({
            amount: payout.amount_cents, currency: "usd", destination: payout.destination, source_transaction: charge.id,
            metadata: Funding.metadata(payment).merge("lightek_ad_payout_id" => payout.id.to_s)
          }, Funding.options.merge(idempotency_key: Funding.key(payment, "payout-#{payout.role}")))
          unless transfer.amount == payout.amount_cents && transfer.destination == payout.destination && transfer.source_transaction == charge.id
            raise Funding::PaymentChanged, "The transfer receipt needs reconciliation."
          end

          payout.update!(transfer_reference: transfer.id)
        end
        payout
      rescue Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable
        raise Funding::Unavailable, "Payout is temporarily unavailable. Please retry."
      end

      def self.payable_charge!(payment)
        raise Funding::Unavailable, "Payment has not settled." unless payment.state == "captured" && payment.placement.delivered_at?

        charge = Funding.load_intent!(payment).latest_charge
        balance = charge.balance_transaction
        unless charge.id == payment.charge_reference && charge.paid && charge.captured && !charge.disputed &&
            charge.amount_refunded.to_i.zero? && balance.respond_to?(:net) && balance.net >= payment.amount_cents &&
            balance.currency == "usd" && balance.status == "available"
          raise Funding::Unavailable, "Funds are not available for payout."
        end

        charge
      end
      private_class_method :payable_charge!

      def self.reconcile_charge!(payment)
        payment.with_lock do
          return unless payment.charge_reference

          charge = Funding.load_intent!(payment).latest_charge
          raise Funding::PaymentChanged, "The charge reference changed." unless charge.id == payment.charge_reference

          if charge.disputed || charge.amount_refunded.to_i.positive?
            payment.update!(state: "held", reconcile_after: 5.minutes.from_now)
            payment.payouts.where.not(transfer_reference: nil).where(reversal_reference: nil).each do |payout|
              transfer = Stripe::Transfer.retrieve(payout.transfer_reference, Funding.options)
              unless transfer.destination == payout.destination && transfer.source_transaction == charge.id
                raise Funding::PaymentChanged, "The transfer reference needs reconciliation."
              end

              # Any refund or dispute freezes this indivisible funded spot.
              reversal = if transfer.amount_reversed == payout.amount_cents
                Stripe::Transfer.list_reversals(transfer.id, { limit: 1 }, Funding.options).data.first
              elsif transfer.amount_reversed.zero?
                Stripe::Transfer.create_reversal(transfer.id, { amount: payout.amount_cents },
                  Funding.options.merge(idempotency_key: Funding.key(payment, "reverse-#{payout.role}")))
              end
              raise Funding::PaymentChanged, "The transfer reversal needs reconciliation." unless reversal&.amount == payout.amount_cents

              payout.update!(reversal_reference: reversal.id)
            end
            payment.update!(reconcile_after: nil)
          elsif payment.state == "held" && payment.payouts.where.not(reversal_reference: nil).none?
            payment.update!(state: "captured", reconcile_after: nil)
          else
            payment.update!(reconcile_after: nil)
          end
        end
      rescue Stripe::StripeError, LightekPayments::PayoutAccounts::Unavailable
        raise Funding::Unavailable, "Charge reconciliation is temporarily unavailable."
      end
    end
  end
end
