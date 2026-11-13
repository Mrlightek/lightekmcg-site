class JurisdictionMonitorJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(monitor_id)
    monitor = LightekCompliance::Monitor.find(monitor_id)
    claimed = nil
    monitor.with_lock do
      return unless monitor.enabled? && monitor.next_run_at <= Time.current
      claimed = Time.current.change(usec: 0)
      monitor.update!(next_run_at: claimed + 1.day)
    end
    LightekCompliance::Access.authorize!(monitor.actor,monitor.employer)
    snapshot = LightekCompliance::Sources.fetch(monitor)
    monitor.with_lock do
      LightekCompliance::Access.authorize!(monitor.actor,monitor.employer)
      monitor.update!(snapshot: snapshot,last_checked_at: Time.current,error_code: nil) if monitor.enabled?
    end
  rescue StandardError => error
    values = {error_code: error.class.name.demodulize}
    values[:enabled] = false if error.is_a?(LightekPeople::Access::Denied)
    monitor&.update_columns(values)
  ensure
    self.class.set(wait_until: monitor.next_run_at).perform_later(monitor.id) if claimed && monitor&.reload&.enabled?
  end
end
