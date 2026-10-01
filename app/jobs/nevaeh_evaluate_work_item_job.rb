# frozen_string_literal: true

class NevaehEvaluateWorkItemJob < ApplicationJob
  queue_as :default

  def perform(work_item_id)
    work_item =
      DymondDispatch::WorkItem.find_by(id: work_item_id)

    return unless work_item
    return unless work_item.finished? || work_item.status == "cancelled"

    plan =
      NevaehOrchestration::PlanBuilder.from_work_item(
        work_item
      )

    outcome =
      NevaehOrchestration::WorkItemOutcome.call(
        work_item
      )

    result =
      NevaehOrchestration::OutcomeHandler.call(
        plan: plan,
        outcome: outcome,
        work_item: work_item
      )

    log_decision(
      work_item: work_item,
      result: result
    )

    result
  rescue NevaehOrchestration::CapabilityRegistry::CapabilityNotFound,
         NevaehOrchestration::CapabilityRegistry::CapabilityDisabled => error

    Rails.logger.error(
      "[Nevaeh] Cannot evaluate WorkItem ##{work_item_id}: " \
      "#{error.class}: #{error.message}"
    )

    raise
  end

  private

  def log_decision(work_item:, result:)
    decision = result.fetch(:decision)

    Rails.logger.info(
      "[Nevaeh] WorkItem ##{work_item.id} " \
      "correlation=#{work_item.correlation_id} " \
      "decision=#{decision.action} " \
      "reason=#{decision.reason.inspect}"
    )
  end
end
