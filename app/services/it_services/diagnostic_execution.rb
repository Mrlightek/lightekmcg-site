# frozen_string_literal: true

module ItServices
  # Executes only explicitly supported read-only checks against enrolled
  # device metadata. No shell, SSH, MDM commands, external network or mutations.
  class DiagnosticExecution
    def self.call!(request:, technician:, code:)
      raise ArgumentError, "Unknown diagnostic runbook" unless DiagnosticRunbooks::CATALOG.key?(code)
      request.with_lock do
        authorization = RemoteDiagnosticAuthorization.verify!(request: request, technician: technician)
        device = request.network_managed_device
        observations = {
          "enrolled" => device.enrolled_at.present?,
          "active" => device.status == "active",
          "heartbeat_recent" => device.last_seen_at.present? && !device.heartbeat_stale?,
          "management_protocol" => device.management_protocol,
          "os_version" => device.os_version
        }
        findings = []
        findings << "Device enrollment missing" unless observations["enrolled"]
        findings << "Device not active" unless observations["active"]
        findings << "Heartbeat missing or stale" unless observations["heartbeat_recent"]
        findings << "Management protocol not reported" if observations["management_protocol"].blank?
        findings << "OS version not reported" if observations["os_version"].blank?
        findings << "Additional #{code} telemetry is unavailable; a full #{code} check was not performed"
        report = {
          "runbook" => code, "request_id" => request.id, "device_id" => device.id,
          "authorization" => authorization, "observations" => observations,
          "findings" => findings, "outcome" => "limited_metadata_only",
          "commands_executed" => false, "remediation_performed" => false,
          "executed_at" => Time.current.iso8601(6)
        }
        ticket = Marlon::Ticket.where(related: request).where.not(status: "resolved")
          .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
        raise ArgumentError, "Linked Nevaeh ticket required" unless ticket
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          handoff = fields.fetch("it_services_handoff", {})
          raise ArgumentError, "Accepted technician handoff required" unless
            %w[accepted rework_requested].include?(handoff["state"]) &&
            handoff["technician_id"] == technician.id &&
            handoff["reservation_id"] == request.reservation_id
          history = Array(fields["it_services_diagnostic_reports"])
          raise ArgumentError, "Diagnostic report limit reached" if history.size >= 100
          fields["it_services_diagnostic_reports"] = history + [report]
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "it_services_diagnostic_#{code}",
            detail: "Read-only #{code} metadata review; no commands executed", actor: technician)
          ItServiceEvent.create!(it_service_request: request, actor: technician,
            from_status: request.status, to_status: request.status,
            note: "Read-only #{code} diagnostic metadata review; no repairs performed")
        end
        report
      end
    end
  end
end
