# frozen_string_literal: true

module NevaehOnboarding
  class SweepJob < ApplicationJob
    queue_as :default

    def perform
      LightekAgency::Trial.where('paid_through > ?', Time.current).where.not(activated_at: nil)
        .find_each { |trial| process_record(trial) { StandingAssignment.start!(trial) } }
      pending_measurements = NevaehResolutionObservation.where(workflow: NevaehImprovement::Agency::KEY, measured_at: nil)
      NevaehOnboardingCase.open_cases.or(NevaehOnboardingCase.where(id: pending_measurements.select(:subject_id))).find_each do |entry|
        process_record(entry) do
          StandingAssignment.advance!(entry)
          NevaehImprovement::Agency.update!(entry)
        end
      end
      operators = NevaehOnboardingCase.select(:operator_id).distinct
      User.where(id: operators, role: 'super_admin').find_each do |operator|
        process_record(operator) do
          Improvement.new(operator).evaluate!
          NevaehImprovement::Cycle.new(operator, NevaehImprovement::Agency::KEY).evaluate!
        end
      end
      NevaehImprovement::PurchasedService.sweep!
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
