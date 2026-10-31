# frozen_string_literal: true

module NevaehIntelligences
  class ProcessBacklogJob < ApplicationJob
    queue_as :default
    BATCH_SIZE = 100
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(ticket_id: nil, after_id: 0, ceiling_id: nil)
      return "disabled" unless TicketBacklog.enabled?
      if ticket_id
        ticket = Marlon::Ticket.find_by(id: ticket_id)
        return "missing" unless ticket
        receipt = receipt_for(ticket)
        return receipt["outcome"] if receipt["state"] == "completed"
        journal!(ticket, "running")
        outcome = TicketBacklog.process!(ticket: ticket)
        journal!(ticket, "completed", outcome: outcome)
        return outcome
      end
      # Fixed high-water mark bounds each sweep; the next cron catches new rows.
      ceiling = ceiling_id || Marlon::Ticket.maximum(:id) || 0
      ids = Marlon::Ticket.where.not(status: "resolved").where("id > ? AND id <= ?", after_id, ceiling)
        .order(:id).limit(BATCH_SIZE).pluck(:id)
      ids.each { |id| self.class.perform_later(ticket_id: id) }
      self.class.perform_later(after_id: ids.last, ceiling_id: ceiling) if ids.length == BATCH_SIZE
      ids.length
    rescue StandardError => error
      if ticket_id && ticket
        count = TicketBacklog.record_failure!(ticket: ticket, error: error)
        if count >= TicketBacklog::MAX_FAILURES
          journal!(ticket, "completed", outcome: "escalated")
          return "escalated"
        end
        journal!(ticket, "retry_pending")
      end
      raise
    end

    private

    def receipt_for(ticket)
      ticket.reload.extra_fields.to_h.deep_stringify_keys.dig("nevaeh_backlog", "job_receipts", job_id).to_h
    end

    def journal!(ticket, state, outcome: nil)
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        backlog = fields.fetch("nevaeh_backlog", {})
        receipts = backlog.fetch("job_receipts", {})
        prior = receipts.fetch(job_id, {})
        return if prior["state"] == "completed"
        receipt = prior.merge("state" => state, "received_at" => prior["received_at"] || Time.current.iso8601(6))
        receipt["outcome"] = outcome if outcome
        receipt["completed_at"] = Time.current.iso8601(6) if state == "completed"
        receipts[job_id] = receipt
        backlog["job_receipts"] = receipts.sort_by { |id, value| [value.fetch("received_at", ""), id] }.last(100).to_h
        fields["nevaeh_backlog"] = backlog
        ticket.update!(extra_fields: fields)
        if state == "completed"
          ticket.log!(action: "nevaeh_backlog_job_completed", detail: {"job_id" => job_id, "outcome" => outcome}.to_json)
        end
      end
    end
  end
end
