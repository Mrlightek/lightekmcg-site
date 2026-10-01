# frozen_string_literal: true

module NevaehOrchestration
  class Intent
    attr_reader \
      :name,
      :instruction,
      :parameters,
      :capability_hint,
      :correlation_id,
      :metadata

    def initialize(
      name:,
      instruction: nil,
      parameters: {},
      capability_hint: nil,
      correlation_id: nil,
      metadata: {}
    )
      @name = name.to_s.strip
      @instruction = instruction.to_s.strip.presence
      @parameters = parameters.to_h.deep_stringify_keys
      @capability_hint = capability_hint.to_s.strip.presence
      @correlation_id = Correlation.normalize(correlation_id)
      @metadata = metadata.to_h.deep_stringify_keys

      validate!
    end

    def to_h
      {
        name: name,
        instruction: instruction,
        parameters: parameters,
        capability_hint: capability_hint,
        correlation_id: correlation_id,
        metadata: metadata
      }.compact
    end

    private

    def validate!
      raise ArgumentError, "intent name is required" if name.blank?
    end
  end
end
