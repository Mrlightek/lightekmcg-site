# frozen_string_literal: true

module NevaehIntelligences
  class GatekeeperIncidentTriage
    PROJECT_CHECKS = %w[deploy_project healthcheck_project].freeze
    HEALTH_ACCEPTANCE = [
      "Verify the original Gatekeeper health check failed on this project and node",
      "Verify the latest follow-up health check on this project and node passed",
      "Confirm the project still reports healthy after that check"
    ].freeze

    def self.for(ticket:, fields:)
      source = fields["gatekeeper"]
      return unless fields["source"] == "gatekeeper" && source.is_a?(Hash)

      unless ticket.related_type == "GatekeeperOperation" && ticket.related_id &&
          ticket.related_id.to_s == source["operation_id"].to_s
        return {"status" => "unverified_ticket_link"}
      end

      operation = GatekeeperOperation.find_by(id: ticket.related_id)
      return {"status" => "missing_operation"} unless operation

      unless operation.capability == source["capability"] &&
          operation.gatekeeper_node_id.to_s == source["node_id"].to_s &&
          operation.gatekeeper_project_id.to_s == source["project_id"].to_s
        return {"status" => "target_mismatch"}
      end

      evidence = {"operation" => receipt(operation)}
      return evidence.merge("status" => "operation_state_changed") unless operation.status == "failed"

      follow_up = latest_follow_up(operation)
      return evidence.merge("status" => "failure_confirmed") unless follow_up

      evidence.merge("status" => "follow_up_recorded", "follow_up" => receipt(follow_up))
    end

    def self.project_health_recovery(ticket:, fields:)
      triage = self.for(ticket: ticket, fields: fields)
      return unless triage&.dig("operation", "capability") == "healthcheck_project" &&
        triage.dig("follow_up", "status") == "succeeded"

      original, follow_up = triage.values_at("operation", "follow_up")
      check = GatekeeperOperation.find_by(id: follow_up.fetch("id"), status: "succeeded", capability: "healthcheck_project",
        gatekeeper_node_id: original.fetch("node_id"), gatekeeper_project_id: original.fetch("project_id"), exit_status: 0)
      return unless check&.started_at && check.completed_at && check.result.to_h["healthy"] == true

      project = GatekeeperProject.find_by(id: check.gatekeeper_project_id,
        gatekeeper_node_id: check.gatekeeper_node_id, status: "healthy")
      return unless project&.last_healthcheck_at && project.last_healthcheck_at >= check.started_at

      triage.merge("project_health_observed_at" => project.last_healthcheck_at.iso8601(6),
        "worker_recovered" => check.result.to_h["worker_recovered"] == true)
    end

    def self.latest_follow_up(operation)
      return unless operation.gatekeeper_project_id && operation.completed_at &&
        PROJECT_CHECKS.include?(operation.capability)

      GatekeeperOperation.where(gatekeeper_node_id: operation.gatekeeper_node_id,
        gatekeeper_project_id: operation.gatekeeper_project_id, capability: operation.capability)
        .where("started_at > ?", operation.completed_at)
        .order(started_at: :desc, id: :desc).first
    end
    private_class_method :latest_follow_up

    def self.receipt(operation)
      {
        "id" => operation.id,
        "capability" => operation.capability,
        "node_id" => operation.gatekeeper_node_id,
        "project_id" => operation.gatekeeper_project_id,
        "status" => operation.status,
        "exit_status" => operation.exit_status,
        "completed_at" => operation.completed_at&.iso8601(6)
      }.compact
    end
    private_class_method :receipt
  end
end
