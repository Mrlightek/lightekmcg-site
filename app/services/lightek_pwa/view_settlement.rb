module LightekPwa
  class ViewSettlement
    class Unavailable < StandardError; end
    def self.options = LightekPayments::PayoutAccounts.options
    def self.hash(value) = value.to_h.deep_stringify_keys
    def self.account!
      account = hash(Stripe::Account.retrieve(nil, options))
      raise Unavailable, 'Platform automatic bank payouts must be paused before reserving creator view funds' unless account.dig('settings', 'payouts', 'schedule', 'interval') == 'manual'
      account
    end
    def self.topup!(reference)
      raise Unavailable, 'Enter a verified platform funding reference' unless reference.to_s.match?(/\Atu_[A-Za-z0-9]+\z/)
      topup = hash(Stripe::Topup.retrieve({id: reference, expand: ['balance_transaction']}, options))
      balance = topup['balance_transaction']
      raise Unavailable, 'View-earnings funds are pending, reversed or unavailable' unless topup['id'] == reference && topup['status'] == 'succeeded' && topup['currency'] == 'usd' &&
        balance.is_a?(Hash) && balance['type'] == 'topup' && balance['source'] == reference && balance['currency'] == 'usd' && balance['status'] == 'available' && balance['available_on'].to_i <= Time.current.to_i && balance['net'].to_i.positive?
      raise Unavailable, 'Test funding cannot release production earnings' if Rails.env.production? && topup['livemode'] != true
      [topup, balance]
    end
    def self.fund!(batch:, actor:, reference:)
      MemberBackends.operator!(batch.site, actor)
      account = account!
      _, balance = topup!(reference)
      batch.site.with_lock do
        batch.reload
        raise Unavailable, 'This batch has a different committed funding source' if batch.funding_reference.present? && batch.funding_reference != reference
        raise Unavailable, 'This funding source is already reserved for another batch' if ViewBatch.where(funding_reference: reference).where.not(id: batch.id).exists?
        raise Unavailable, 'Funding does not cover the complete creator liability' if balance['net'].to_i < batch.creator_liability_cents
        # The database uniqueness constraint also protects simultaneous funding
        # across sites. One top-up is reserved for exactly one finalized batch.
        batch.update!(funding_reference: reference, funding_balance_transaction: balance.fetch('id'),
          funded_cents: balance.fetch('net'), platform_account: account.fetch('id'), state: 'funded', funded_at: Time.current)
        batch.view_earnings.where(state: %w[awaiting_funding held]).update_all(state: 'available')
      end
      batch
    end
    def self.reserve_cents
      # Never spend the principal owed to support creators to pay view earnings.
      views = ViewEarning.joins(:view_batch).where(lightek_pwa_view_batches: {state: %w[funded funding_held]}).where.not(state: 'transferred').sum(:amount_cents)
      support = CreatorEarning.where.not(state: %w[transferred reversed]).sum(:principal_cents)
      views + support
    end
    def self.recover_transfer(earning)
      return hash(Stripe::Transfer.retrieve(earning.transfer_reference, options)) if earning.transfer_reference.present?
      return unless earning.transfer_requested_at
      # A retry after the provider's idempotency-retention window must never
      # blindly create a second transfer. Search the actual destination history.
      cursor = nil
      10.times do
        query = {destination: earning.destination_account, limit: 100, created: {gte: earning.transfer_requested_at.to_i - 60}}
        query[:starting_after] = cursor if cursor
        page = hash(Stripe::Transfer.list(query, options))
        found = Array(page['data']).select { |row| row.dig('metadata', 'lightek_view_earning_key') == earning.transfer_key }
        raise Unavailable, 'Duplicate provider transfer receipts require reconciliation' if found.size > 1
        return found.first if found.one?
        break unless page['has_more']
        cursor = page.fetch('data').last.fetch('id')
      end
      raise Unavailable, 'An older transfer request needs provider reconciliation before retrying' if earning.transfer_requested_at < 23.hours.ago
      nil
    end
    def self.verify!(earning, receipt)
      raise Unavailable, 'View transfer receipt does not match its reserved earning' unless receipt['amount'] == earning.amount_cents && receipt['currency'] == 'usd' && receipt['destination'] == earning.destination_account &&
        receipt.dig('metadata', 'lightek_view_earning_key') == earning.transfer_key && receipt['amount_reversed'].to_i.zero? && !receipt['reversed']
    end
    def self.serialized
      connection = ApplicationRecord.connection
      postgres = connection.adapter_name == 'PostgreSQL'
      if postgres
        locked = connection.select_value('SELECT pg_try_advisory_lock(9183319001)')
        raise Unavailable, 'Another creator view transfer is running; retry shortly' unless locked == true || locked == 't'
      end
      yield
    ensure
      connection.select_value('SELECT pg_advisory_unlock(9183319001)') if postgres && locked
    end
    def self.release!(earning:, actor:)
      raise Unavailable, 'This earning belongs to another creator' unless earning.user_id == actor.id
      raise Unavailable, 'View-earnings release is not open yet' unless ENV['LIGHTEK_VIEW_PAYOUTS_ENABLED'] == 'true'
      serialized do
        earning.reload
        return earning if earning.state == 'transferred'
        batch = earning.view_batch.reload
        raise Unavailable, 'This batch is not funded' unless batch.state == 'funded'
        account = account!
        raise Unavailable, 'Platform funding account changed' unless account['id'] == batch.platform_account
        begin
          _, funding = topup!(batch.funding_reference)
        rescue Unavailable
          batch.update!(state: 'funding_held')
          batch.view_earnings.where(state: 'available').update_all(state: 'held')
          raise
        end
        raise Unavailable, 'Funding receipt changed' unless funding['id'] == batch.funding_balance_transaction && funding['net'].to_i >= batch.creator_liability_cents
        raise Unavailable, 'No payable earnings' unless earning.amount_cents.positive? && %w[available transfer_pending].include?(earning.state)
        raise Unavailable, 'Complete payout verification first' unless LightekPayments::PayoutAccounts.status(actor)[:state] == 'ready'
        raise Unavailable, 'Payout destination changed; reconcile the pending transfer' if earning.destination_account.present? && earning.destination_account != actor.stripe_connect_account_id
        existing = recover_transfer(earning)
        unless existing
          balance = hash(Stripe::Balance.retrieve(options))
          available = Array(balance['available']).select { |row| row['currency'] == 'usd' }.sum { |row| row['amount'].to_i }
          raise Unavailable, 'Available funds do not cover reserved creator liabilities' if available < reserve_cents
          earning.update!(state: 'transfer_pending', destination_account: actor.stripe_connect_account_id,
            transfer_requested_at: earning.transfer_requested_at || Time.current)
          existing = hash(Stripe::Transfer.create({amount: earning.amount_cents, currency: 'usd', destination: earning.destination_account,
            transfer_group: "pwa-view-#{batch.id}", metadata: {lightek_view_earning_key: earning.transfer_key, lightek_view_batch_id: batch.id.to_s}},
            options.merge(idempotency_key: "pwa-view-#{earning.transfer_key}")))
        end
        verify!(earning, existing)
        earning.update!(state: 'transferred', transfer_reference: existing.fetch('id'))
      end
      earning
    end
  end
end
