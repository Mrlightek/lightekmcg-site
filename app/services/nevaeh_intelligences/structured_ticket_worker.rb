# frozen_string_literal: true
module NevaehIntelligences
  module StructuredTicketWorker
    module_function
    def perform(action, payload)
      raise StructuredTicket::Invalid, "Unsupported structured operation" unless action == "execute"
      StructuredExecution.execute!(ticket: Marlon::Ticket.find(payload.fetch("ticket_id")), reservation: payload.fetch("reservation_id"))
    end
  end
end
