class AccountingRefreshJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(automation_id)
    record = LightekAccounting::Automation.find(automation_id)
    claimed = nil
    record.with_lock do
      return unless record.enabled? && record.next_run_at <= Time.current
      claimed = Time.current.change(usec: 0)
      interval = record.data.fetch('cadence') == 'weekly' ? 7.days : 1.day
      record.update!(last_run_at: claimed,next_run_at: claimed + interval,error_code: nil)
    end
    raise LightekAccounting::Access::Denied, 'Authenticator enrollment is required' unless LightekIdentity::Mfa.enabled?(record.actor)
    access = LightekAccounting::Access.new(actor: record.actor,employer: record.book.employer).require!(:read)
    data = record.data
    year = data.dig('tax_inputs','year') || Time.current.in_time_zone(record.book.timezone).year
    report = LightekAccounting::Reports.profit_loss(book: record.book,first: Date.new(year,1,1),last: Date.new(year,12,31))
    output = {'report'=>report,'calculated_at'=>Time.current.iso8601}
    if data['action'] == 'tax_reserve'
      raise ArgumentError, 'Resolve uncategorized rows before automated tax estimation' if report['uncategorized_count'].positive?
      inputs = data.fetch('tax_inputs').merge('profit_cents'=>report.fetch('tax_profit_cents'))
      output['tax_estimate'] = LightekAccounting::TaxEstimate.calculate(inputs)
    end
    record.with_lock do
      access.require!(:read)
      return unless record.enabled? && record.last_run_at == claimed
      record.update!(data: data.merge('latest'=>output))
      LightekAccounting::AuditEvent.record!(actor: record.actor,record: record,action: 'accounting_worker_completed')
    end
  rescue StandardError => error
    values = {error_code: error.class.name.demodulize}
    values[:enabled] = false if error.is_a?(LightekAccounting::Access::Denied)
    record&.update_columns(values)
  ensure
    if claimed && record&.reload&.enabled?
      self.class.set(wait_until: record.next_run_at).perform_later(record.id)
    end
  end
end
