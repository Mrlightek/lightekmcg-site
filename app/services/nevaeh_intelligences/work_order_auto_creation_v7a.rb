# frozen_string_literal: true

module NevaehIntelligences
  # Coordinates creation of a review-only WorkOrder for a valid ticket.
  # Native WorkOrder I/O is supplied by a validated adapter at the real call site.
  # Never dispatches, approves or treats a capability match as authorization.
  class WorkOrderAutoCreationV7a
    class Rejected < StandardError; end

    def self.ensure_for_ticket!(ticket:, adapter:)
      raise Rejected, 'ticket missing' unless ticket && ticket.respond_to?(:id) && ticket.id
      %i[read validate template attach].each do |method|
        raise Rejected, "adapter missing #{method}" unless adapter.respond_to?(method)
      end

      existing = adapter.read(ticket: ticket)
      if existing
        return outcome('existing_valid', existing) if adapter.validate(ticket: ticket, order: existing)
        # Invalid orders are never approved or overwritten. Create a new review-only
        # revision through the adapter; it must retain the prior audit record.
      end

      candidate = adapter.template(ticket: ticket)
      raise Rejected, 'no work order template' unless candidate.is_a?(Hash)
      candidate = candidate.dup
      candidate['gatekeeper_approved'] = false
      candidate['execution_enabled'] = false
      candidate['production_allowed'] = false
      candidate['release_approved'] = false
      candidate['status'] = 'review_required'
      candidate['supersedes_invalid_order'] = !!existing
      raise Rejected, 'generated work order invalid' unless adapter.validate(ticket: ticket, order: candidate)

      # Adapter.attach must atomically create if absent, or append a new revision
      # while retaining an invalid prior record. No overwrite or dispatch allowed.
      attached = adapter.attach(ticket: ticket, order: candidate, previous: existing)
      raise Rejected, 'work order attachment invalid' unless attached && adapter.validate(ticket: ticket, order: attached)
      %w[gatekeeper_approved execution_enabled production_allowed release_approved].each do |flag|
        raise Rejected, 'attachment unexpectedly authorized' unless attached[flag] == false
      end
      outcome('created_review_required', attached)
    end

    def self.outcome(state, order)
      { 'state' => state, 'work_order' => order, 'dispatch_performed' => false, 'authorization_granted' => false }.freeze
    end
    private_class_method :outcome
  end
end
