# frozen_string_literal: true

module NevaehIntelligences
  class ReconcileTicketJob < ApplicationJob
    queue_as :default

    # Retry for up to approximately five minutes, then preserve a pending
    # ticket for human inspection rather than reporting a false success.
    def perform(ticket_id, attempt = 0)
      ticket = Marlon::Ticket.find(ticket_id)
      if ticket.extra_fields.to_h.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute"
        outcome = StructuredExecution.reconcile!(ticket: ticket)
        self.class.set(wait: 10.seconds, queue: queue_name).perform_later(ticket_id, attempt + 1) if outcome == "pending" && attempt < 29
        return outcome
      end
      # Missing receipts require inspection: never infer linkage or retry.
      state = ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh", {})
      if state["work_item_id"].blank?
        evidence = RecoveryEvidenceV2f.for_ticket(ticket)
        Rails.logger.warn("Nevaeh recovery manual review: ticket_id=#{ticket.id} classification=#{evidence.fetch('classification')} work_item_ids=#{evidence.fetch('work_item_ids').inspect}")
        return "manual_review"
      end
      # Linked receipts must also be checked against *all* work items sharing
      # this reservation; a valid-looking linked item does not rule out a twin.
      evidence = RecoveryEvidenceV2f.for_ticket(ticket)
      classification = evidence.fetch("classification")
      unless %w[queued working_or_interrupted completed_unverified terminal_failure_review].include?(classification)
        detail = {
          "classification" => classification,
          "reservation_id" => evidence["reservation_id"],
          "linked_work_item_id" => state["work_item_id"],
          "work_item_ids" => evidence.fetch("work_item_ids"),
          "automatic_retry_allowed" => false
        }
        ticket.log!(action: "nevaeh_recovery_manual_review", detail: detail.to_json)
        Rails.logger.warn("Nevaeh linked recovery manual review: ticket_id=#{ticket.id} classification=#{classification} work_item_ids=#{detail.fetch('work_item_ids').inspect}")
        return "manual_review"
      end
      outcome = TicketExecution.reconcile!(ticket: ticket)
      return outcome unless outcome == "pending"
      if attempt < 29
        self.class.set(wait: 10.seconds).perform_later(ticket_id, attempt + 1)
      else
        ticket.log!(action: "nevaeh_reconciliation_timeout", detail: "Work item still pending after 30 checks")
      end
      outcome
    end
  end
end
