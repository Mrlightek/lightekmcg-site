# frozen_string_literal: true

module NevaehOrchestration
  class WorkItemOutcome
    def self.call(work_item)
      new(work_item).call
    end

    def initialize(work_item)
      @work_item = work_item
    end

    def call
      case work_item.status
      when "done"
        successful_outcome

      when "failed"
        failed_outcome

      when "cancelled"
        cancelled_outcome

      else
        raise ArgumentError,
              "WorkItem ##{work_item.id} is not terminal: #{work_item.status.inspect}"
      end
    end

    private

    attr_reader :work_item

    def successful_outcome
      Outcome.new(
        status: "succeeded",
        result: work_item.result.to_h,
        work_item_id: work_item.id,
        subject: work_item.subject,
        correlation_id: work_item.correlation_id,
        metadata: common_metadata
      )
    end

    def failed_outcome
      Outcome.new(
        status: "failed",
        result: work_item.result.to_h,
        error_class: "DymondDispatch::WorkItemFailure",
        error_message: work_item.error,
        work_item_id: work_item.id,
        subject: work_item.subject,
        correlation_id: work_item.correlation_id,
        metadata: common_metadata
      )
    end

    def cancelled_outcome
      Outcome.new(
        status: "cancelled",
        result: work_item.result.to_h,
        work_item_id: work_item.id,
        subject: work_item.subject,
        correlation_id: work_item.correlation_id,
        metadata: common_metadata
      )
    end

    def common_metadata
      {
        "attempts" => work_item.attempts.to_i,
        "queue" => work_item.queue,
        "handler" => work_item.handler,
        "kind" => work_item.kind
      }
    end
  end
end
