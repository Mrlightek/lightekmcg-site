# frozen_string_literal: true
module NevaehIntelligences
  class WorkflowRunJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(id)
      run = NevaehWorkflowRun.find(id)
      return unless run.status == "queued"
      raise WorkOrder::Invalid, "Ticket execution is disabled by the server configuration" unless TicketBacklog.enabled?
      ticket = WorkflowRunner.materialize!(run)
      # Existing backlog, KB resolution, Gatekeeper, Dispatch and verification own execution.
      ProcessBacklogJob.perform_later(ticket_id: ticket.id)
      run.update!(status: "dispatched", error: nil)
    rescue WorkOrder::Invalid, ActiveRecord::RecordInvalid => error
      run&.update!(status: "blocked", error: error.message.to_s.first(2000))
    end
  end
end
