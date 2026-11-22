# frozen_string_literal: true

module NevaehOnboarding
  class SweepJob < ApplicationJob
    queue_as :default

    def perform
      LightekAgency::Trial.where('paid_through > ?', Time.current).where.not(activated_at: nil)
        .find_each { |trial| process_record(trial) { StandingAssignment.start!(trial) } }
      NevaehOnboardingCase.open_cases.find_each { |entry| process_record(entry) { StandingAssignment.advance!(entry) } }
      operators = NevaehOnboardingCase.select(:operator_id).distinct
      User.where(id: operators, role: 'super_admin').find_each do |operator|
        process_record(operator) { Improvement.new(operator).evaluate! }
      end
    end

    private

    def process_record(record)
      yield
    rescue StandardError => error
      Rails.logger.error("[Nevaeh onboarding] #{record.class.name} ##{record.id}: #{error.class}")
      record.update_columns(blocker: 'workflow_error', escalated_at: Time.current) if record.is_a?(NevaehOnboardingCase)
    end
  end
end
