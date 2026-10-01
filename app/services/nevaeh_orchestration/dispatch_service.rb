# frozen_string_literal: true

module NevaehOrchestration
  class DispatchService
    def self.call(plan:)
      new(plan: plan).call
    end

    def initialize(plan:)
      @plan = plan
    end

    def call
      DymondDispatch::Dispatch.open(
        kind: plan.capability,
        handler: plan.handler,
        subject: plan.subject,
        args: plan.args,
        queue: plan.queue,
        priority: plan.priority,
        dispositions: dispositions,
        correlation_id: plan.correlation_id
      )
    end

    private

    attr_reader :plan

    def dispositions
      result = [
        {
          "kind" => "nevaeh",
          "on" => "any"
        }
      ]

      realtime = plan.realtime.to_h.deep_stringify_keys
      stream = resolve_stream(realtime)

      if stream.present?
        result << {
          "kind" => "broadcast",
          "stream" => stream,
          "on" => "any",
          "event_type" => "#{plan.capability}.finished",
          "include_result" =>
            ActiveModel::Type::Boolean.new.cast(
              realtime["include_result"]
            )
        }
      end

      result
    end

    def resolve_stream(realtime)
      explicit = realtime["stream"].to_s.presence
      return explicit if explicit

      template =
        realtime["stream_template"].to_s.presence

      return nil unless template

      template.gsub(
        "{subject_id}",
        plan.subject&.id.to_s
      )
    end
  end
end
