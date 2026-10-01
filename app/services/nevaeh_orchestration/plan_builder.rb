# frozen_string_literal: true

module NevaehOrchestration
  class PlanBuilder
    def self.call(
      capability:,
      subject: nil,
      args: [],
      instruction: nil,
      parameters: {},
      context: {},
      correlation_id: nil
    )
      capability_record =
        capability.is_a?(NevaehCapability) ?
          capability :
          CapabilityRegistry.fetch!(capability)

      capability_record.build_plan(
        subject: subject,
        args: args,
        instruction: instruction,
        parameters: parameters,
        context: context,
        correlation_id: correlation_id
      )
    end

    def self.from_work_item(work_item)
      capability = CapabilityRegistry.fetch!(work_item.kind)

      capability.build_plan(
        subject: work_item.subject,
        args: work_item.args,
        correlation_id: work_item.correlation_id,
        context: {
          "work_item_id" => work_item.id,
          "attempts" => work_item.attempts
        }
      )
    end
  end
end
