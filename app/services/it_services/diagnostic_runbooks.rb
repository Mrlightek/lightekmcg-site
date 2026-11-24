# frozen_string_literal: true

module ItServices
  # Approved diagnostic catalog. These are instructions and checks, NOT shell
  # commands. Any eventual executor must use a separately authorized Gatekeeper
  # capability and verify consent at execution time.
  class DiagnosticRunbooks
    CATALOG = {
      "connectivity" => {
        "title" => "Network connectivity",
        "checks" => ["Confirm device enrollment", "Check heartbeat freshness",
          "Inspect managed network connection status", "Record connectivity findings"]
      },
      "performance" => {
        "title" => "System performance",
        "checks" => ["Record reported slowdown", "Review available resource metrics",
          "Check storage capacity and resource pressure", "Document baseline and follow-up"]
      },
      "security" => {
        "title" => "Security posture",
        "checks" => ["Verify endpoint management enrollment", "Review available security alerts",
          "Check patch compliance where reported", "Escalate suspected compromise"]
      },
      "backup" => {
        "title" => "Backup and recovery readiness",
        "checks" => ["Identify configured backup policy", "Inspect last reported backup status",
          "Check recovery-point age", "Request separately authorized restore test"]
      }
    }.freeze

    def self.for_request!(request:, actor:, code:)
      raise ArgumentError, "Unknown diagnostic runbook" unless CATALOG.key?(code)
      authorization = RemoteDiagnosticAuthorization.verify!(request: request, technician: actor)
      {
        "runbook" => code,
        "title" => CATALOG.fetch(code).fetch("title"),
        "checks" => CATALOG.fetch(code).fetch("checks"),
        "authorization" => authorization,
        "execution" => "manual_only",
        "commands_executed" => false
      }
    end
  end
end
