# frozen_string_literal: true
module Marlon
  class TicketEvent < ApplicationRecord
    self.table_name = "marlon_ticket_events"

    belongs_to :ticket, class_name: "Marlon::Ticket", inverse_of: :events
    belongs_to :actor,  class_name: "User", optional: true

    validates :action, presence: true

    after_create :log_submission_event, if: -> { ticket.events.count == 1 }

    private

    # No-op placeholder — the FIRST event on a fresh ticket is usually
    # "Ticket submitted" itself, created explicitly by the controller.
    # This callback intentionally does nothing extra; kept as a documented
    # hook point for later (e.g. firing a notify disposition on first event).
    def log_submission_event; end
  end
end
