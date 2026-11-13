module LightekAccounting
  class Reconcile
    def self.proof(account:,first:,last:,starting:,ending:,selected:)
      raise ArgumentError, 'Invalid reconciliation period' if last < first || first < account.opening_on
      prior = account.reconciliations.where(status: 'final').order(ends_on: :desc).first
      if prior
        raise ArgumentError, 'Reconcile consecutive periods using the previous ending balance' unless first == prior.ends_on.next_day && starting == prior.data.fetch('ending_cents')
      else
        raise ArgumentError, 'First reconciliation must begin at the account opening balance date' unless first == account.opening_on && starting == account.data.fetch('opening_cents')
      end
      Money.integer!(starting)
      Money.integer!(ending)
      scope = account.transactions.where('posted_on <= ?',last)
      scope = scope.where('reconciliation_id IS NULL OR posted_on > ?',prior.ends_on) if prior
      rows = scope.to_a
      chosen = rows.select { |row| selected.include?(row.id) }
      raise ArgumentError, 'Selection contains missing or previously reconciled transactions' unless chosen.length == selected.length && chosen.all? { |row| row.reconciliation_id.nil? }
      uncleared = rows.select { |row| row.reconciliation_id.nil? && !selected.include?(row.id) }
      cleared_sum = chosen.sum(&:amount_cents)
      deposits = uncleared.select { |row| row.amount_cents.positive? }.sum(&:amount_cents)
      checks = -uncleared.select { |row| row.amount_cents.negative? }.sum(&:amount_cents)
      baseline = prior ? prior.data.fetch('book_balance_cents') : account.data.fetch('opening_cents')
      new_rows = prior ? rows.select { |row| row.posted_on > prior.ends_on } : rows
      book_balance = baseline + new_rows.sum(&:amount_cents)
      { 'starting_cents'=>starting,'ending_cents'=>ending,'selected_ids'=>selected.sort,'cleared_movements_cents'=>cleared_sum,
        'deposits_in_transit_cents'=>deposits,'outstanding_checks_cents'=>checks,'book_balance_cents'=>book_balance,
        'cleared_difference_cents'=>starting + cleared_sum - ending,'book_difference_cents'=>ending + deposits - checks - book_balance,
        'uncleared_ids'=>uncleared.map(&:id).sort }
    end
    def self.finalize!(access:,account:,first:,last:,starting:,ending:,selected:)
      access.require!(:review)
      raise Access::Denied unless account.book.employer_id == access.employer.id
      account.with_lock do
        ids = Array(selected).map { |id| Integer(id.to_s,10) }.uniq
        values = proof(account: account,first: first,last: last,starting: starting,ending: ending,selected: ids)
        raise ArgumentError, 'Reconciliation differences must both be zero before finalizing' unless values['cleared_difference_cents'].zero? && values['book_difference_cents'].zero?
        record = Reconciliation.new(book: account.book,bank_account: account,actor: access.actor,starts_on: first,ends_on: last,status: 'final')
        record.data = values
        record.save!
        account.transactions.where(id: ids).each { |row| row.update!(reconciliation: record) }
        AuditEvent.record!(actor: access.actor,record: record,action: 'reconciliation_finalized')
        record
      end
    end
    def self.reopen!(access:,record:)
      access.require!(:review)
      raise Access::Denied unless record.book.employer_id == access.employer.id
      record.bank_account.with_lock do
        latest = record.bank_account.reconciliations.where(status: 'final').order(ends_on: :desc).first
        raise ArgumentError, 'Only the latest finalized period can be reopened' unless latest&.id == record.id
        Transaction.where(reconciliation: record).update_all(reconciliation_id: nil)
        record.update!(status: 'superseded')
        AuditEvent.record!(actor: access.actor,record: record,action: 'reconciliation_reopened')
      end
    end
  end
end
