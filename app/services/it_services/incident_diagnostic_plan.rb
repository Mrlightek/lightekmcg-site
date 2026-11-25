# frozen_string_literal: true

module ItServices
  # Nevaeh triage plan uses existing non-executable runbook descriptions.
  # Device telemetry never authorizes an executable capability.
  class IncidentDiagnosticPlan
    RUNBOOKS = {
      "heartbeat_missing" => "connectivity",
      "heartbeat_stale" => "connectivity",
      "not_active" => "connectivity",
      "not_enrolled" => "connectivity",
      "telemetry_missing_or_stale" => "connectivity",
      "disk_pressure" => "performance",
      "endpoint_protection_alert" => "security",
      "patches_available" => "security",
      "backup_recovery_test_failed" => "backup",
      "staged_restore_failed" => "backup",
      "live_restore_failed" => "backup",
      "patch_deployment_failed" => "security",
      "backup_failed" => "backup"
    }.freeze

    MAINTENANCE = {
      "patches_available" => ItDeviceMaintenanceAction::PATCH_DEPLOYMENT,
      "patch_deployment_failed" => ItDeviceMaintenanceAction::PATCH_DEPLOYMENT,
      "backup_recovery_test_failed" => ItDeviceMaintenanceAction::RECOVERY_CHECK,
      "live_restore_failed" => ItDeviceMaintenanceAction::STAGED_RESTORE,
      "staged_restore_failed" => ItDeviceMaintenanceAction::STAGED_RESTORE
    }.freeze

    def self.for(incident)
      code = RUNBOOKS[incident.finding_code]
      catalog = DiagnosticRunbooks::CATALOG[code]
      {
        "runbook" => code,
        "checks" => catalog ? catalog.fetch("checks") : ["Review device enrollment and incident history"],
        "execution" => "manual_only",
        "recommended_maintenance" => MAINTENANCE[incident.finding_code],
        "consent_required_for_remote_actions" => true,
        "commands_executed" => false,
        "repair_verified" => false
      }
    end
  end
end
