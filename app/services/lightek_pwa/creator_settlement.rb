module LightekPwa
  class CreatorSettlement
    class Unavailable < StandardError; end
    def self.options
      LightekPayments::PayoutAccounts.options
    end
    def self.hash(value) = value.to_h.deep_stringify_keys
    def self.id(value) = value.is_a?(Hash) ? value['id'] : value
    def self.charge_for(order)
      opts = options
      if order.payment_provider == 'stripe'
        session = hash(Stripe::Checkout::Session.retrieve(order.payment_reference, opts))
        expected = LightekCommerce::PaymentIdentity.metadata(order).stringify_keys
        raise Unavailable, 'Payment identity needs review' unless session['payment_status'] == 'paid' && expected.all? { |k, v| session.fetch('metadata', {})[k] == v }
        intent = id(session['payment_intent'])
        invoice = id(session['invoice'])
      elsif order.payment_provider == 'stripe_invoice'
        invoice = order.payment_reference
      end
      if intent.blank? && invoice.present?
        data = hash(Stripe::Invoice.retrieve({id: invoice, expand: ['payments']}, opts))
        raise Unavailable, 'Invoice has not settled' unless data['status'] == 'paid' && data['currency'] == order.currency && data['amount_paid'] == order.total_cents
        intent = id(data['payment_intent']) # Older pinned API versions.
        unless intent
          payments = data.fetch('payments', {})
          rows = Array(payments['data']).select { |p| p['status'] == 'paid' }
          raise Unavailable, 'Split or multi-payment invoice needs reconciliation' unless !payments['has_more'] && rows.one? && rows.first['amount_paid'] == order.total_cents && rows.first.dig('payment', 'type') == 'payment_intent'
          intent = id(rows.first.dig('payment', 'payment_intent'))
        end
      end
      raise Unavailable, 'Confirmed payment source is not available yet' if intent.blank?
      data = hash(Stripe::PaymentIntent.retrieve({id: intent, expand: ['latest_charge.balance_transaction']}, opts))
      raise Unavailable, 'Payment source does not match the earning' unless data['status'] == 'succeeded' && data['currency'] == order.currency && data['amount_received'] == order.total_cents
      charge = data['latest_charge']
      raise Unavailable, 'Payment source is not expanded' unless charge.is_a?(Hash) && charge['payment_intent'] == intent && charge['amount'] == order.total_cents
      charge
    end
    def self.refresh!(earning)
      reverse = false
      earning.with_lock do
        order = earning.order
        raise Unavailable, 'Earning is not backed by verified payment' unless order.paid_at? && %w[paid fulfilled partially_refunded refunded].include?(order.status)
        charge = charge_for(order)
        raise Unavailable, 'Payment source changed; manual review required' if earning.charge_reference.present? && earning.charge_reference != charge['id']
        earning.update!(charge_reference: charge.fetch('id'))
        problem = !charge['paid'] || charge['disputed'] || charge['amount_refunded'].to_i.positive? || order.refunds.where(status: %w[pending succeeded]).exists?
        if problem
          earning.update!(state: earning.reversal_reference.present? ? 'reversed' : 'held', hold_reason: 'Refund or dispute under review')
          reverse = earning.transfer_reference.present? && earning.reversal_reference.blank?
        elsif !%w[transferred reversed transfer_pending].include?(earning.state)
          balance = charge['balance_transaction']
          funded = balance.is_a?(Hash) && balance['status'] == 'available' && balance['currency'] == order.currency && balance['net'].to_i >= earning.principal_cents && balance['available_on'].to_i <= Time.current.to_i
          earning.update!(state: funded ? 'available' : 'held', hold_reason: funded ? nil : 'Waiting for payment funds or fee coverage',
            available_at: balance.is_a?(Hash) && balance['available_on'].to_i.positive? ? Time.at(balance['available_on']) : nil)
        end
      end
      # Commit the hold before the external reversal. A lost response must not
      # restore this earning to available/transferred or announce a paid gift.
      if reverse
        reversal = Stripe::Transfer.create_reversal(earning.transfer_reference, {amount: earning.principal_cents},
          options.merge(idempotency_key: LightekCommerce::PaymentIdentity.key(earning.order, 'creator-support-reversal')))
        earning.with_lock { earning.update!(state: 'reversed', reversal_reference: reversal.id) }
      end
      earning
    end
    def self.release!(earning:, actor:)
      raise Unavailable, 'This earning belongs to another creator' unless earning.creator_payment.creator_id == actor.id
      raise Unavailable, 'Creator payouts are not open yet' unless ENV['LIGHTEK_CREATOR_PAYOUTS_ENABLED'] == 'true'
      refresh!(earning)
      earning.with_lock do
        return earning if earning.state == 'transferred'
        raise Unavailable, earning.hold_reason || 'Earning is not available' unless %w[available transfer_pending].include?(earning.state)
        raise Unavailable, 'Complete payout verification before requesting earnings' unless LightekPayments::PayoutAccounts.status(actor)[:state] == 'ready'
        if earning.destination_account.present? && earning.destination_account != actor.stripe_connect_account_id
          raise Unavailable, 'Payout account changed during a transfer; reconcile before retrying'
        end
        if earning.state == 'transfer_pending' && (earning.transfer_requested_at.nil? || earning.transfer_requested_at < 23.hours.ago)
          raise Unavailable, 'This older uncertain transfer needs provider reconciliation before another release attempt'
        end
        # Stored before the request. Retrying uses the same destination/key.
        earning.update!(state: 'transfer_pending', destination_account: actor.stripe_connect_account_id, transfer_requested_at: earning.transfer_requested_at || Time.current)
      end
      return earning if earning.state == 'transferred'
      transfer = Stripe::Transfer.create({amount: earning.principal_cents, currency: earning.order.currency,
          destination: earning.destination_account, source_transaction: earning.charge_reference,
          metadata: {lightek_creator_earning_id: earning.id.to_s, lightek_host_key: earning.order.payment_namespace}},
          options.merge(idempotency_key: LightekCommerce::PaymentIdentity.key(earning.order, 'creator-support-transfer')))
        raise Unavailable, 'Transfer receipt needs reconciliation' unless transfer.amount == earning.principal_cents && transfer.destination == earning.destination_account && transfer.source_transaction == earning.charge_reference
      earning.with_lock do
        raise Unavailable, 'Transfer destination changed' unless earning.destination_account == transfer.destination
        earning.update!(state: 'transferred', transfer_reference: transfer.id, hold_reason: nil)
      end
      refresh!(earning)
      earning
    end
    def self.payment_event!(event)
      return false unless %w[charge.refunded charge.dispute.created charge.dispute.closed].include?(event.type)
      object = hash(event.data.object)
      charge = event.type == 'charge.refunded' ? object['id'] : id(object['charge'])
      CreatorEarning.where(charge_reference: charge).find_each { |earning| CreatorSettlementJob.perform_later(earning.id) } if charge.present?
      true
    end
  end
end
