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
        return TicketBacklog.process!(ticket: ticket)
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
        return "escalated" if count >= TicketBacklog::MAX_FAILURES
      end
      raise
    end
  end
end
