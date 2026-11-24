# frozen_string_literal: true

module ItServices
  # Opens a single Nevaeh-visible technical ticket per active finding.
  # Tickets are observational only and never authorize device commands.
  class IncidentEscalation
    def self.call!(incident:)
      raise ArgumentError, "Incident is not open" unless incident.status == "open"
      device = incident.network_managed_device
      device.with_lock do
        incident.reload
        return unless incident.status == "open" && device.managed_monitoring_enabled?
        raise ArgumentError, "Device ownership changed" unless device.owner_id == incident.owner_id
        raise ArgumentError, "Inactive customer" unless LightekPeople::LifecycleAccess.active?(incident.owner)

        ticket = Marlon::Ticket.where(related: incident).order(:id).last
        return ticket if ticket

        plan = IncidentDiagnosticPlan.for(incident)
        ticket = Marlon::Ticket.create!(
          title: "Managed device: #{incident.finding_code.humanize}",
          description: "Nevaeh detected an agent-reported or connectivity finding. Device ##{incident.network_managed_device_id}. Verify evidence and managed-service authorization before taking action.",
          category: "technical", priority: priority_for(incident.finding_code),
          submitted_by: incident.owner, related: incident,
          assigned_team: "Technical", assigned_rep: "Nevaeh",
          extra_fields: {
            "source" => "it_managed_device_monitoring",
            "incident_id" => incident.id,
            "device_id" => incident.network_managed_device_id,
            "execution_authorized" => false,
            "resolution_verified" => false,
            "diagnostic_plan" => plan
          }
        )
        ticket.log!(action: "Managed device finding detected", detail: incident.finding_code)
        ticket
      end
    end

    def self.priority_for(code)
      case code
      when "endpoint_protection_alert", "backup_failed", "backup_recovery_test_failed", "staged_restore_failed", "patch_deployment_failed" then "high"
      when "heartbeat_missing", "heartbeat_stale", "disk_pressure" then "medium"
      else "low"
      end
    end
  end
end
