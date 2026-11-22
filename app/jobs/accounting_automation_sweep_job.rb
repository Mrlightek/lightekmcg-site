# frozen_string_literal: true

class AccountingAutomationSweepJob < ApplicationJob
  queue_as :default

  def perform
    LightekAccounting::Automation.where(enabled: true).where("next_run_at <= ?", Time.current)
      .find_each { |automation| AccountingRefreshJob.perform_later(automation.id) }
  end
end
