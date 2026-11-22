# frozen_string_literal: true

module NevaehIntelligences
  # Closes an infrastructure incident from persisted evidence produced by the
  # native health check, using the existing ticket analysis and audit trail.
  class GatekeeperIncidentRecovery
    def self.reconcile!(ticket:)
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        backlog = fields.fetch("nevaeh_backlog", {})
        state = fields.fetch("nevaeh", {})
        return if ticket.status == "resolved" || state.values_at("reservation_id", "work_item_id", "execution_status").any?(&:present?)
        return unless backlog.dig("incident_triage", "status") == "follow_up_recorded"

        order = WorkOrder.read!(ticket: ticket)
        return unless order["work_type"] == "fix" && order["intent_key"] == "healthcheck_project" &&
          order.dig("inputs", "operation_id").to_s == ticket.related_id.to_s &&
          order["acceptance_criteria"] == GatekeeperIncidentTriage::HEALTH_ACCEPTANCE &&
          order.dig("execution_policy", "execution_enabled") == false

        triage = GatekeeperIncidentTriage.project_health_recovery(ticket: ticket, fields: fields)
        return unless triage

        verified_at = Time.current
        proof = triage.slice("operation", "follow_up", "project_health_observed_at", "worker_recovered")
          .merge("verified_at" => verified_at.iso8601(6))
        fields["nevaeh"] = state.merge(
          "intent_key" => "healthcheck_project", "execution_status" => "verified",
          "verification_mode" => "gatekeeper_project_health_recovery", "verification" => proof
        )
        fields["nevaeh_backlog"] = backlog.merge(
          "status" => "verified_resolved", "blockers" => [], "incident_triage" => triage.slice("status", "operation", "follow_up"),
          "updated_at" => verified_at.iso8601
        )
        ticket.update!(status: "resolved", resolved_at: verified_at, extra_fields: fields)
        ticket.log!(action: "nevaeh_project_health_verified", detail: proof.to_json)
        "resolved"
      end
    end
  end
end
