# frozen_string_literal: true

module NevaehOrchestration
  class OutcomeHandler
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
      decision = Evaluator.call(
        plan: plan,
        outcome: outcome,
        work_item: work_item
      )

      case decision.action
      when "complete", "cancel"
        resolution(decision: decision)

      when "retry"
        retry_resolution(decision)

      when "alternate"
        alternate_resolution(decision)

      when "escalate"
        escalation_resolution(decision)

      else
        raise "Unsupported Nevaeh decision #{decision.action.inspect}"
      end
    end

    private

    attr_reader :plan, :outcome, :work_item

    def retry_resolution(decision)
      raise ArgumentError, "work_item is required for retry" unless work_item

      retried = DymondDispatch::Dispatcher.retry(work_item.id)

      raise(
        "WorkItem ##{work_item.id} could not be retried from status #{work_item.status.inspect}"
      ) unless retried

      resolution(
        decision: decision,
        work_item: retried
      )
    end

    def alternate_resolution(decision)
      dispositions = realtime_dispositions

      alternate = DymondDispatch::Dispatch.open(
        kind: plan.capability,
        handler: decision.next_handler,
        subject: plan.subject,
        args: plan.args,
        queue: decision.next_queue || plan.queue,
        priority: plan.priority,
        dispositions: dispositions,
        correlation_id: plan.correlation_id
      )

      resolution(
        decision: decision,
        work_item: alternate
      )
    end

    def escalation_resolution(decision)
      ticket = Escalation.call(
        plan: plan,
        outcome: outcome,
        decision: decision,
        work_item: work_item
      )

      resolution(
        decision: decision,
        work_item: work_item,
        ticket: ticket
      )
    end

    def realtime_dispositions
      realtime = plan.realtime.to_h.deep_stringify_keys
      stream = realtime["stream"].to_s.presence

      return [] unless stream

      [
        {
          "kind" => "broadcast",
          "stream" => stream,
          "on" => "any",
          "include_result" =>
            ActiveModel::Type::Boolean.new.cast(
              realtime["include_result"]
            )
        }
      ]
    end

    def resolution(decision:, work_item: nil, ticket: nil)
      {
        decision: decision,
        work_item: work_item,
        ticket: ticket,
        correlation_id: plan.correlation_id
      }
    end
  end
end
