# frozen_string_literal: true

module NevaehOrchestration
  class Plan
    attr_reader \
      :intent,
      :capability,
      :handler,
      :subject,
      :args,
      :queue,
      :priority,
      :expected_outcome,
      :failure_policy,
      :realtime,
      :knowledge_article_ids,
      :context,
      :correlation_id

    def initialize(
      intent:,
      capability:,
      handler:,
      subject: nil,
      args: [],
      queue: "default",
      priority: 5,
      expected_outcome: {},
      failure_policy: {},
      realtime: {},
      knowledge_article_ids: [],
      context: {},
      correlation_id: nil
    )
      @intent = intent
      @capability = capability.to_s.strip
      @handler = handler.to_s.strip
      @subject = subject
      @args = Array(args)
      @queue = queue.to_s.strip.presence || "default"
      @priority = priority.to_i
      @expected_outcome = expected_outcome.to_h.deep_stringify_keys
      @failure_policy = failure_policy.to_h.deep_stringify_keys
      @realtime = realtime.to_h.deep_stringify_keys
      @knowledge_article_ids = Array(knowledge_article_ids).compact
      @context = context.to_h.deep_stringify_keys
      @correlation_id =
        Correlation.normalize(
          correlation_id ||
          intent.try(:correlation_id)
        )

      validate!
    end

    def subject_ref
      return nil unless subject

      {
        type: subject.class.name,
        id: subject.respond_to?(:id) ? subject.id : nil
      }.compact
    end

    def to_h
      {
        capability: capability,
        handler: handler,
        subject: subject_ref,
        args: args,
        queue: queue,
        priority: priority,
        expected_outcome: expected_outcome,
        failure_policy: failure_policy,
        realtime: realtime,
        knowledge_article_ids: knowledge_article_ids,
        context: context,
        correlation_id: correlation_id,
        intent: intent.respond_to?(:to_h) ? intent.to_h : intent
      }
    end

    private

    def validate!
      raise ArgumentError, "intent is required" unless intent
      raise ArgumentError, "capability is required" if capability.blank?
      raise ArgumentError, "handler is required" if handler.blank?

      unless priority.between?(0, 10)
        raise ArgumentError, "priority must be between 0 and 10"
      end
    end
  end
end
