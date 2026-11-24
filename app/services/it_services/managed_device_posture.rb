# frozen_string_literal: true

module ItServices
  # Observational baseline only. This does not establish security, patch,
  # backup, or performance compliance and never grants remote execution.
  class ManagedDevicePosture
    def self.evaluate(device:, owner:)
      raise ArgumentError, "Device owner authorization required" unless owner&.persisted? &&
        device.owner_id.present? && device.owner_id == owner.id
      findings = []
      findings << "retired" if device.status == "retired"
      findings << "not_enrolled" if device.enrolled_at.nil?
      findings << "not_active" unless device.status == "active"
      findings << "heartbeat_missing" if device.last_seen_at.nil?
      findings << "heartbeat_stale" if device.last_seen_at.present? &&
        device.last_seen_at < NetworkManagedDevice::HEARTBEAT_TIMEOUT.ago
      telemetry = device.health_telemetry.to_h
      telemetry_fresh = device.health_telemetry_at.present? &&
        device.health_telemetry_at >= 15.minutes.ago
      if telemetry_fresh
        findings << "endpoint_protection_alert" if telemetry["endpoint_protection"] == "alert"
        findings << "backup_failed" if telemetry["backup_status"] == "failed"
        findings << "patches_available" if telemetry["patch_status"] == "updates_available"
        findings << "disk_pressure" if telemetry["disk_percent"].to_f >= 90 && telemetry.key?("disk_percent")
      else
        findings << "telemetry_missing_or_stale"
      end
      patch_inventory, backup_sample, staged_restore_status, patch_deployment_status = maintenance_evidence(device)
      findings << "patches_available" if patch_inventory.fetch("available_update_count", 0).positive?
      backup_sample_status = backup_sample["status"]
      findings << "backup_recovery_test_failed" if %w[mismatch unavailable].include?(backup_sample_status)
      findings << "staged_restore_failed" if staged_restore_status == "attention_required"
      findings << "patch_deployment_failed" if patch_deployment_status == "attention_required"
      {
        device_id: device.id,
        owner_id: owner.id,
        standard: "lightek_managed_device_v1",
        status: findings.empty? ? "connectivity_observed" : "attention_required",
        findings: findings.uniq,
        telemetry_fresh: telemetry_fresh,
        reported_telemetry: telemetry_fresh ? telemetry : {},
        backup_sample_status: backup_sample_status,
        staged_restore_status: staged_restore_status,
        patch_deployment_status: patch_deployment_status,
        evaluated_at: Time.current.iso8601(6),
        limitations: "Agent-reported metrics are not independently verified. Maintenance results cover their approved package or backup only.",
        remote_execution_authorized: false
      }
    end

    def self.maintenance_evidence(device)
      return [{}, {}, nil, nil] unless device.persisted? && device.enrolled_at? && device.managed_monitoring_enabled?

      now = Time.current
      actions = ItDeviceMaintenanceAction.where(network_managed_device: device, owner_id: device.owner_id)
        .where(created_at: device.enrolled_at..now)
      reports = actions.where(status: "reported")
        .where(reported_at: [24.hours.ago, device.enrolled_at].max..now).order(reported_at: :desc, id: :desc)
      [reports.find_by(action_code: "check_patch_status")&.result || {},
        reports.find_by(action_code: "verify_backup_recovery")&.result || {},
        operation_status(actions, code: "stage_backup_restore", artifact: :expected_recovery_digest, now: now),
        operation_status(actions, code: "deploy_apt_patch", artifact: :patch_target, now: now)]
    end

    def self.operation_status(actions, code:, artifact:, now:)
      scoped = actions.where(action_code: code)
      timed_out = scoped.where(status: "approved").where.not(claimed_at: nil).where(expires_at: ..now)
      column = ItDeviceMaintenanceAction.connection.quote_column_name(artifact)
      last_by_artifact = scoped.where(status: "reported").or(timed_out)
        .select(Arel.sql("DISTINCT ON (#{column}) CASE WHEN status = 'approved' THEN 'unconfirmed' ELSE result ->> 'status' END AS outcome"))
        .order(artifact, updated_at: :desc, id: :desc)
      outcomes = ItDeviceMaintenanceAction.from(last_by_artifact, :it_device_maintenance_actions)
      return "attention_required" if outcomes.where.not(outcome: "verified").exists?
      return "verified" if outcomes.exists?

      nil
    end
    private_class_method :maintenance_evidence, :operation_status
  end
end
