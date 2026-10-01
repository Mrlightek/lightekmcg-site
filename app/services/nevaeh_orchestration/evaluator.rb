# frozen_string_literal: true

module NevaehOrchestration
  class Evaluator
    def self.call(plan:, outcome:, work_item: nil)
      new(
        plan: plan,
        outcome: outcome,
        work_item: work_item
      ).call
    end

    def initialize(plan:, outcome:, work_item: nil)
      @plan = plan
      @outcome = outcome
      @work_item = work_item
    end

    def call
      validate_correlation!

      return complete_decision if successful?
      return cancel_decision if cancelled?
      return explicit_retry_decision if outcome.retry?
      return retry_decision if retry_available?
      return alternate_decision if alternate_available?

      escalate_decision
    end

    private

    attr_reader :plan, :outcome, :work_item

    def successful?
      return false unless outcome.succeeded?

      expected = plan.expected_outcome.to_h
      return true if expected.empty?

      expected.all? do |key, expected_value|
        actual_value =
          outcome.result[key.to_s] ||
          outcome.result[key.to_sym]

        expectation_matches?(
          key.to_s,
          expected_value,
          actual_value
        )
      end
    end

    def expectation_matches?(key, expected_value, actual_value)
      case key
      when "artifact_kind"
        artifact_kinds =
          Array(
            outcome.result["artifact_kinds"] ||
            outcome.result[:artifact_kinds]
          ).map(&:to_s)

        actual_value.to_s == expected_value.to_s ||
          artifact_kinds.include?(expected_value.to_s)
      else
        actual_value.to_s == expected_value.to_s
      end
    end

    def cancelled?
      outcome.status == "cancelled"
    end

    def retry_available?
      return false unless outcome.failed?

      allowed = failure_policy.fetch("retries", 0).to_i
      attempts < allowed
    end

    def alternate_available?
      return false unless outcome.failed?

      alternate_handler.present?
    end

    def attempts
      return work_item.attempts.to_i if work_item&.respond_to?(:attempts)

      outcome.metadata.fetch("attempts", 0).to_i
    end

    def failure_policy
      plan.failure_policy.to_h.deep_stringify_keys
    end

    def alternate_handler
      failure_policy["alternate_handler"].to_s.presence
    end

    def alternate_queue
      failure_policy["alternate_queue"].to_s.presence ||
        plan.queue
    end

    def escalation_enabled?
      ActiveModel::Type::Boolean.new.cast(
        failure_policy.fetch("escalate", true)
      )
    end

    def complete_decision
      Decision.new(
        action: "complete",
        reason: "Expected outcome satisfied.",
        correlation_id: correlation_id,
        capability: plan.capability,
        work_item_id: outcome.work_item_id,
        knowledge_article_ids: plan.knowledge_article_ids,
        metadata: {
          expected_outcome: plan.expected_outcome,
          result: outcome.result
        }
      )
    end

    def cancel_decision
      Decision.new(
        action: "cancel",
        reason: "Execution was cancelled.",
        correlation_id: correlation_id,
        capability: plan.capability,
        work_item_id: outcome.work_item_id,
        knowledge_article_ids: plan.knowledge_article_ids
      )
    end

    def explicit_retry_decision
      Decision.new(
        action: "retry",
        reason: "Outcome explicitly requested another attempt.",
        correlation_id: correlation_id,
        capability: plan.capability,
        work_item_id: outcome.work_item_id,
        knowledge_article_ids: plan.knowledge_article_ids,
        metadata: {
          attempts: attempts
        }
      )
    end

    def retry_decision
      Decision.new(
        action: "retry",
        reason: "Failure is within the configured retry policy.",
        correlation_id: correlation_id,
        capability: plan.capability,
        work_item_id: outcome.work_item_id,
        knowledge_article_ids: plan.knowledge_article_ids,
        metadata: {
          attempts: attempts,
          retries_allowed: failure_policy.fetch("retries", 0).to_i
        }
      )
    end

    def alternate_decision
      Decision.new(
        action: "alternate",
        reason: "Primary execution path failed and an alternate handler is configured.",
        correlation_id: correlation_id,
        capability: plan.capability,
        work_item_id: outcome.work_item_id,
        knowledge_article_ids: plan.knowledge_article_ids,
        next_handler: alternate_handler,
        next_queue: alternate_queue,
        metadata: {
          failed_handler: plan.handler,
          error_class: outcome.error_class,
          error_message: outcome.error_message
        }
      )
    end

    def escalate_decision
      if escalation_enabled?
        Decision.new(
          action: "escalate",
          reason: escalation_reason,
          correlation_id: correlation_id,
          capability: plan.capability,
          work_item_id: outcome.work_item_id,
          knowledge_article_ids: plan.knowledge_article_ids,
          metadata: {
            handler: plan.handler,
            attempts: attempts,
            error_class: outcome.error_class,
            error_message: outcome.error_message,
            expected_outcome: plan.expected_outcome,
            result: outcome.result
          }
        )
      else
        Decision.new(
          action: "complete",
          reason: "Execution failed, but policy does not permit escalation.",
          correlation_id: correlation_id,
          capability: plan.capability,
          work_item_id: outcome.work_item_id,
          knowledge_article_ids: plan.knowledge_article_ids,
          metadata: {
            unsuccessful: true,
            error_class: outcome.error_class,
            error_message: outcome.error_message
          }
        )
      end
    end

    def escalation_reason
      if outcome.succeeded?
        "Worker completed, but the result did not satisfy the expected outcome."
      else
        "Known retry and alternate execution paths are exhausted."
      end
    end

    def correlation_id
      plan.correlation_id
    end

    def validate_correlation!
      ids = [
        plan.correlation_id,
        outcome.correlation_id,
        work_item&.try(:correlation_id)
      ].compact.map(&:to_s).reject(&:blank?).uniq

      return if ids.one?

      raise ArgumentError,
            "correlation mismatch across plan/outcome/work item: #{ids.join(', ')}"
    end
  end
end
