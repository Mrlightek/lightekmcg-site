module ItServices
  class DiagnosticInterpreter
    def self.call!(request:, actor:)
      snapshot = DeviceHealthSnapshot.call!(request: request, actor: actor)
      findings = []
      if snapshot[:status] == "offline"
        findings << { code: "device_offline", severity: "attention", summary: "Device is offline", recommendation: "Confirm the device is powered on and connected before scheduling remote diagnostics." }
      elsif snapshot[:heartbeat_stale]
        findings << { code: "stale_heartbeat", severity: "attention", summary: "Device heartbeat is overdue", recommendation: "Check device connectivity and management agent health." }
      end
      if snapshot[:enrolled_at].nil?
        findings << { code: "not_enrolled", severity: "information", summary: "Device enrollment is incomplete", recommendation: "Complete enrollment before requesting remote diagnostics." }
      end
      if snapshot[:last_seen_at].nil?
        findings << { code: "no_heartbeat", severity: "information", summary: "No device heartbeat recorded", recommendation: "Confirm device enrollment and network connectivity." }
      end
      findings << { code: "no_alerts_from_metadata", severity: "information", summary: "No connectivity warnings detected in available metadata", recommendation: "For malware, performance or disk health, schedule a separate authorized diagnostic session." } if findings.empty?
      {
        request_id: request.id,
        generated_at: Time.current.iso8601,
        source: "existing_mdm_metadata",
        limitations: "Metadata-only review. No live malware scan, CPU benchmark, disk analysis or repair was performed.",
        device: snapshot,
        findings: findings,
        recommended_next_step: findings.any? { |f| f[:severity] == "attention" } ? "Check connectivity before further diagnostics" : "Arrange a diagnostic session if symptoms persist"
      }
    end
  end
end
