# frozen_string_literal: true

module NevaehOrchestration
  class Event
    attr_reader \
      :event_type,
      :source,
      :subject,
      :actor,
      :context,
      :payload,
      :occurred_at,
      :correlation_id

    def initialize(
      event_type:,
      source:,
      subject: nil,
      actor: nil,
      context: {},
      payload: {},
      occurred_at: Time.current,
      correlation_id: nil
    )
      @event_type = event_type.to_s.strip
      @source = source.to_s.strip
      @subject = subject
      @actor = actor
      @context = normalize_hash(context)
      @payload = normalize_hash(payload)
      @occurred_at = occurred_at
      @correlation_id = Correlation.normalize(correlation_id)

      validate!
    end

    def subject_ref
      record_ref(subject)
    end

    def actor_ref
      record_ref(actor)
    end

    def to_h
      {
        event_type: event_type,
        source: source,
        subject: subject_ref,
        actor: actor_ref,
        context: context,
        payload: payload,
        occurred_at: occurred_at,
        correlation_id: correlation_id
      }
    end

    private

    def validate!
      raise ArgumentError, "event_type is required" if event_type.blank?
      raise ArgumentError, "source is required" if source.blank?
      raise ArgumentError, "context must be a Hash" unless context.is_a?(Hash)
      raise ArgumentError, "payload must be a Hash" unless payload.is_a?(Hash)
    end

    def normalize_hash(value)
      value.nil? ? {} : value.to_h.deep_stringify_keys
    end

    def record_ref(record)
      return nil unless record

      {
        type: record.class.name,
        id: record.respond_to?(:id) ? record.id : nil
      }.compact
    end
  end
end
