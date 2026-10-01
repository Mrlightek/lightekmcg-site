# frozen_string_literal: true

module NevaehOrchestration
  class IntentResolver
    class UnresolvedIntent < StandardError; end

    def self.call(
      event:,
      capability_hint: nil,
      instruction: nil,
      parameters: {}
    )
      new(
        event: event,
        capability_hint: capability_hint,
        instruction: instruction,
        parameters: parameters
      ).call
    end

    def initialize(
      event:,
      capability_hint: nil,
      instruction: nil,
      parameters: {}
    )
      @event = event
      @capability_hint = capability_hint.to_s.presence
      @instruction = instruction
      @parameters = parameters.to_h
    end

    def call
      capability = resolve_capability

      Intent.new(
        name: capability.intent_name,
        instruction:
          instruction.presence ||
          event.payload["instruction"],
        parameters:
          event.payload.merge(parameters.deep_stringify_keys),
        capability_hint: capability.slug,
        correlation_id: event.correlation_id,
        metadata: {
          "event_type" => event.event_type,
          "source" => event.source
        }
      )
    end

    private

    attr_reader \
      :event,
      :capability_hint,
      :instruction,
      :parameters

    def resolve_capability
      if capability_hint
        return CapabilityRegistry.fetch!(
          capability_hint
        )
      end

      capability =
        NevaehCapability
          .enabled
          .where(
            "event_types @> ?::jsonb",
            [event.event_type].to_json
          )
          .first

      return capability if capability

      raise UnresolvedIntent,
            "Nevaeh does not know how to handle event " \
            "#{event.event_type.inspect}"
    end
  end
end
