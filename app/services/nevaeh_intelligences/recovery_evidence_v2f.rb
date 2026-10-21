# frozen_string_literal: true

module NevaehIntelligences
  # Evidence-only review for a single logical Studio operation. This service
  # never authorizes, requeues, alters ticket state or executes the handler.
  class RecoveryEvidenceV2f
    KIND = 'studio.project.create'
    HANDLER = 'Studio::Workers::ProjectCreation'
    TERMINAL = %w[done failed cancelled error dead].freeze

    def self.for_ticket(ticket)
      raise ArgumentError, 'Persisted Marlon ticket required' unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      state = ticket.extra_fields.to_h.deep_stringify_keys.fetch('nevaeh', {})
      reservation = state['reservation_id'].to_s
      return { 'classification' => 'missing_reservation', 'work_item_ids' => [], 'automatic_retry_allowed' => false } if reservation.empty?
      items = DymondDispatch::WorkItem.where(subject_type: 'Marlon::Ticket', subject_id: ticket.id, correlation_id: reservation).to_a
      classify(items: items, ticket_id: ticket.id, reservation_id: reservation, linked_work_item_id: state['work_item_id'])
    end

    def self.classify(items:, ticket_id:, reservation_id:, linked_work_item_id: nil)
      reservation = reservation_id.to_s
      raise ArgumentError, 'Reservation required' if reservation.empty?
      matching = Array(items).select do |item|
        item.subject_type.to_s == 'Marlon::Ticket' && item.subject_id.to_s == ticket_id.to_s &&
          item.correlation_id.to_s == reservation && item.kind.to_s == KIND && item.handler.to_s == HANDLER
      end
      ids = matching.map(&:id)
      mismatched_link = linked_work_item_id.present? && !ids.map(&:to_s).include?(linked_work_item_id.to_s)
      classification = if mismatched_link
        'linked_item_mismatch'
      elsif matching.length > 1
        'duplicate_work_items'
      elsif matching.empty?
        'no_matching_work_item'
      else
        item = matching.first
        case item.status.to_s
        when 'done' then 'completed_unverified'
        when 'failed', 'cancelled', 'error', 'dead' then 'terminal_failure_review'
        when 'working' then 'working_or_interrupted'
        when 'queued' then 'queued'
        else 'unknown_status'
        end
      end
      { 'classification' => classification, 'work_item_ids' => ids,
        'automatic_retry_allowed' => false, 'reservation_id' => reservation }
    end
  end
end
