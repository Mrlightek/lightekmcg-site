# frozen_string_literal: true

module NevaehIntelligences
  # Read-only snapshot of ticket work-order and linked execution evidence.
  # Never dispatches, reconciles, or modifies the ticket during a page request.
  class TicketEvidence
    attr_reader :ticket

    def initialize(ticket)
      @ticket = ticket
    end

    def work_order
      ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh_work_order", {})
    end

    def state
      ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh", {})
    end

    def present?
      work_order.present? || state.present?
    end

    def linked_work_item
      return nil if state["work_item_id"].blank?
      item = DymondDispatch::WorkItem.find_by(id: state["work_item_id"])
      return nil unless item
      return nil unless item.kind.to_s == state["intent_key"].to_s
      return nil if state["correlation_id"].blank?
      return nil unless item.correlation_id.to_s == state["correlation_id"].to_s
      item
    end

    def work_item_status
      return "not dispatched" if state["work_item_id"].blank?
      linked_work_item&.status.to_s.presence || "unavailable / mismatch"
    end

    def verification
      state.fetch("verification", {})
    end

    def dispatch_receipt
      state.fetch("dispatch_receipt", {})
    end
  end
end
