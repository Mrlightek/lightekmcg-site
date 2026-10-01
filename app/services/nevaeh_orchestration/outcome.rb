# frozen_string_literal: true

module NevaehOrchestration
  class Outcome
    STATUSES = %w[
      succeeded
      failed
      retry
      escalated
      cancelled
    ].freeze

    attr_reader \
      :status,
      :result,
      :error_class,
      :error_message,
      :work_item_id,
      :subject,
      :correlation_id,
      :metadata

    def initialize(
      status:,
      result: {},
      error_class: nil,
      error_message: nil,
      work_item_id: nil,
      subject: nil,
      correlation_id: nil,
      metadata: {}
    )
      @status = status.to_s
      @result = result.to_h.deep_stringify_keys
      @error_class = error_class.to_s.presence
      @error_message = error_message.to_s.presence
      @work_item_id = work_item_id
      @subject = subject
      @correlation_id = Correlation.normalize(correlation_id)
      @metadata = metadata.to_h.deep_stringify_keys

      validate!
    end

    def succeeded?
      status == "succeeded"
    end

    def failed?
      status == "failed"
    end

    def retry?
      status == "retry"
    end

    def escalated?
      status == "escalated"
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
        status: status,
        result: result,
        error_class: error_class,
        error_message: error_message,
        work_item_id: work_item_id,
        subject: subject_ref,
        correlation_id: correlation_id,
        metadata: metadata
      }.compact
    end

    private

    def validate!
      unless STATUSES.include?(status)
        raise ArgumentError,
              "invalid outcome status #{status.inspect}; expected one of #{STATUSES.join(', ')}"
      end
    end
  end
end
