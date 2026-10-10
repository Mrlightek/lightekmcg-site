# frozen_string_literal: true

module NevaehIntelligences
  class Dispatch
    class Unavailable < StandardError; end

    def self.call(intent_key:, payload: {}, actor: nil, execute: false, correlation_id: nil)
      new(intent_key: intent_key, payload: payload, actor: actor,
          execute: execute, correlation_id: correlation_id).call
    end

    def initialize(intent_key:, payload:, actor:, execute:, correlation_id:)
      @intent_key = intent_key.to_s
      @payload = payload.to_h.deep_stringify_keys
      @actor = actor
      @execute = execute
      @correlation_id = correlation_id || SecureRandom.uuid
    end

    def call
      record = NevaehIntelligence.available.includes(:nevaeh_capability).find_by(intent_key: @intent_key)
      raise Unavailable, "Intelligence #{@intent_key.inspect} is not published and enabled" unless record

      capability = record.nevaeh_capability
      action = record.dispatch_action
      event_type = Array(capability.event_types).first
      raise Unavailable, 'Capability has no registered event type' if event_type.blank?
      raise Unavailable, 'Capability has no dispatch action' if action.blank?

      receipt = {
        'intent_key' => record.intent_key,
        'intelligence_id' => record.id,
        'capability' => capability.slug,
        'target_model' => record.target_model,
        'operation' => record.operation,
        'action' => action,
        'event_type' => event_type,
        'execution_mode' => record.execution_mode,
        'correlation_id' => @correlation_id
      }
      return receipt.merge('status' => 'preview', 'inputs' => @payload) unless @execute

      raise Unavailable, 'Authenticated actor is required for execution' unless @actor
      request = ::Nevaeh.handle(
        event_type: event_type,
        source: 'nevaeh_intelligence',
        actor: @actor,
        payload: @payload,
        capability_hint: capability.slug,
        args: [action, @payload],
        context: { 'intelligence_id' => record.id, 'intent_key' => record.intent_key },
        correlation_id: @correlation_id
      )
      receipt.merge('status' => 'dispatched', 'work_item_id' => request.work_item.id)
    end
  end
end
