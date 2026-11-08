# frozen_string_literal: true
module NevaehIntelligences
  class FactoryWorker
    def self.perform(action, payload = {})
      raise WorkOrder::Invalid, 'Unknown construction action' unless action == 'execute'
      ticket = Marlon::Ticket.find(payload.fetch('ticket_id'))
      release = NevaehConstructionRelease.find(payload.fetch('release_id'))
      actor = Factory::Execution.authorize!(release: release, ticket: ticket)
      Factory::Execution.perform!(release: release, inputs: payload.fetch('data'), ticket: ticket, actor: actor)
    end
  end
end
