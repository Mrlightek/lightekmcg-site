module Gatekeeper
  class InfrastructureController < ApplicationController
    def index
      @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
      @operations = GatekeeperOperation.includes(:gatekeeper_node, :gatekeeper_project).recent_first.limit(20)
      @support_tickets = Marlon::Ticket
        .where(related_type: "GatekeeperOperation")
        .where.not(status: "resolved")
        .order(created_at: :desc)
        .limit(20)
      @metrics = Metrics.summary
    end
  end
end
