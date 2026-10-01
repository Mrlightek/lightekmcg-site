# frozen_string_literal: true

module NevaehOrchestration
  class Decision
    ACTIONS = %w[
      complete
      retry
      alternate
      escalate
      cancel
    ].freeze

    attr_reader \
      :action,
      :reason,
      :correlation_id,
      :capability,
      :work_item_id,
      :knowledge_article_ids,
      :next_handler,
      :next_queue,
      :metadata

    def initialize(
      action:,
      reason:,
      correlation_id:,
      capability: nil,
      work_item_id: nil,
      knowledge_article_ids: [],
      next_handler: nil,
      next_queue: nil,
      metadata: {}
    )
      @action = action.to_s
      @reason = reason.to_s
      @correlation_id = Correlation.normalize(correlation_id)
      @capability = capability.to_s.presence
      @work_item_id = work_item_id
      @knowledge_article_ids = Array(knowledge_article_ids).compact
      @next_handler = next_handler.to_s.presence
      @next_queue = next_queue.to_s.presence
      @metadata = metadata.to_h.deep_stringify_keys

      validate!
    end

    def complete?  = action == "complete"
    def retry?     = action == "retry"
    def alternate? = action == "alternate"
    def escalate?  = action == "escalate"
    def cancel?    = action == "cancel"

    def to_h
      {
        action: action,
        reason: reason,
        correlation_id: correlation_id,
        capability: capability,
        work_item_id: work_item_id,
        knowledge_article_ids: knowledge_article_ids,
        next_handler: next_handler,
        next_queue: next_queue,
        metadata: metadata
      }.compact
    end

    private

    def validate!
      unless ACTIONS.include?(action)
        raise ArgumentError,
              "invalid decision action #{action.inspect}; expected one of #{ACTIONS.join(', ')}"
      end

      raise ArgumentError, "decision reason is required" if reason.blank?
    end
  end
end
