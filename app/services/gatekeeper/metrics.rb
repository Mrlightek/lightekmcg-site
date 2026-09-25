module Gatekeeper
  class Metrics
    def self.summary(since: 7.days.ago)
      operations = GatekeeperOperation.where(created_at: since..)

      tickets = Marlon::Ticket.where(
        related_type: "GatekeeperOperation",
        created_at: since..
      )

      open_tickets = Marlon::Ticket
        .where(related_type: "GatekeeperOperation")
        .where.not(status: "resolved")

      total = operations.count
      interventions = tickets.count

      {
        operations: total,
        succeeded: operations.where(status: "succeeded").count,
        failed: operations.where(status: "failed").count,
        support_tickets: tickets.count,
        open_support_tickets: open_tickets.count,
        human_interventions: interventions,
        marlon_dependency_rate: total.zero? ? 0.0 : interventions.to_f / total
      }
    end
  end
end
