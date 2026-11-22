# frozen_string_literal: true

class AccountingRefreshJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)

  def perform(automation_id)
    record = LightekAccounting::Automation.find_by(id: automation_id)
    return unless record

    record.with_lock do
      return unless record.enabled? && record.next_run_at <= Time.current

      now = Time.current.change(usec: 0)
      data = record.data
      interval = data.fetch("cadence") == "weekly" ? 7.days : 1.day
      begin
        LightekAccounting::Automation.transaction(requires_new: true) do
          access = accounting_access!(record)
          output = work!(record, data, access, now)
          record.data = data.merge("latest" => output)
          record.update!(last_run_at: now, next_run_at: now + interval, error_code: nil)
          LightekAccounting::AuditEvent.record!(actor: access.actor, record: record, action: "accounting_worker_completed")
        end
      rescue LightekAccounting::Access::Denied => error
        record.reload.update!(enabled: false, last_run_at: now, error_code: error.class.name.demodulize)
      rescue StandardError => error
        record.reload.update!(last_run_at: now, next_run_at: now + interval, error_code: error.class.name.demodulize)
        Rails.logger.error("Accounting worker #{record.id} failed (#{error.class})")
      end
    end
    self.class.set(wait_until: record.next_run_at).perform_later(record.id) if record.enabled?
  rescue ActiveJob::EnqueueError => error
    Rails.logger.warn("Accounting worker enqueue failed for #{automation_id} (#{error.class})")
  end

  private

  def accounting_access!(record)
    unless LightekIdentity::Mfa.enabled?(record.actor)
      raise LightekAccounting::Access::Denied, "Authenticator enrollment is required"
    end

    LightekAccounting::Access.new(actor: record.actor, employer: record.book.employer).require!(:read)
  end

  def work!(record, data, access, now)
    output = {"calculated_at" => now.iso8601}
    if data["action"] == "categorize"
      access.require!(:admin)
      return output.merge(LightekAccounting::Rules.apply_saved!(access: access, book: record.book))
    end

    year = data.dig("tax_inputs", "year") || now.in_time_zone(record.book.timezone).year
    report = LightekAccounting::Reports.profit_loss(book: record.book, first: Date.new(year, 1, 1), last: Date.new(year, 12, 31))
    output["report"] = report
    if data["action"] == "tax_reserve"
      raise ArgumentError, "Resolve uncategorized rows before automated tax estimation" if report["uncategorized_count"].positive?

      inputs = data.fetch("tax_inputs").merge("profit_cents" => report.fetch("tax_profit_cents"))
      output["tax_estimate"] = LightekAccounting::TaxEstimate.calculate(inputs)
    end
    output
  end
end
