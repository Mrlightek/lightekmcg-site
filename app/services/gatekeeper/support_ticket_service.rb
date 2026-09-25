require "securerandom"

module Gatekeeper
  class SupportTicketService
    def self.open_for_failure!(operation:, error:, knowledge_articles: [])
      existing = Marlon::Ticket.find_by(
        related_type: "GatekeeperOperation",
        related_id: operation.id
      )
      return existing if existing

      ticket = Marlon::Ticket.new(
        category: "technical",
        title: "Gatekeeper: #{operation.capability.humanize} failed",
        description: description_for(operation, error),
        priority: "high",
        urgency: 8,
        status: "open",
        organization_name: "Lightek MCG",
        assigned_team: "Technical",
        assigned_rep: "Nevaeh / Gatekeeper",
        related_type: "GatekeeperOperation",
        related_id: operation.id,
        extra_fields: extra_fields_for(operation, error, knowledge_articles)
      )

      save_with_number_fallback!(ticket)

      record_event!(
        ticket,
        action: "gatekeeper_escalated",
        detail: "Gatekeeper exhausted the currently known execution path for #{operation.capability}."
      )

      if knowledge_articles.any?
        record_event!(
          ticket,
          action: "kb_consulted",
          detail: "Knowledge consulted: #{knowledge_articles.map(&:article_id).join(', ')}"
        )
      end

      ticket
    end

    def self.record_event!(ticket, action:, detail:, actor_id: nil)
      Marlon::TicketEvent.create!(
        ticket_id: ticket.id,
        actor_id: actor_id,
        action: action,
        detail: detail
      )
    rescue StandardError => e
      Rails.logger.warn("[Gatekeeper::SupportTicketService] Ticket event failed: #{e.class}: #{e.message}")
      nil
    end

    def self.description_for(operation, error)
      <<~TEXT
        Gatekeeper could not complete an automated operation.

        Capability: #{operation.capability}
        Node: #{operation.gatekeeper_node&.name}
        Project: #{operation.gatekeeper_project&.name || "N/A"}
        Requested by: #{operation.requested_by}
        Error: #{error.class}: #{error.message}

        This ticket was created automatically because the known Gatekeeper execution path did not complete successfully.
      TEXT
    end
    private_class_method :description_for

    def self.extra_fields_for(operation, error, knowledge_articles)
      {
        "source" => "gatekeeper",
        "gatekeeper" => {
          "operation_id" => operation.id,
          "capability" => operation.capability,
          "node_id" => operation.gatekeeper_node_id,
          "project_id" => operation.gatekeeper_project_id,
          "exit_status" => operation.exit_status,
          "error_class" => error.class.name,
          "error_message" => error.message,
          "requested_by" => operation.requested_by,
          "kb_articles_consulted" => knowledge_articles.map(&:article_id),
          "known_recovery_exhausted" => true
        }
      }
    end
    private_class_method :extra_fields_for

    def self.save_with_number_fallback!(ticket)
      ticket.save!
    rescue ActiveRecord::RecordInvalid
      raise unless ticket.errors[:number].present?

      ticket.number ||= "LT-GK-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(2).upcase}"
      ticket.save!
    end
    private_class_method :save_with_number_fallback!
  end
end
