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
      {
        device_id: device.id,
        owner_id: owner.id,
        standard: "lightek_managed_device_v1",
        status: findings.empty? ? "connectivity_observed" : "attention_required",
        findings: findings.uniq,
        telemetry_fresh: telemetry_fresh,
        reported_telemetry: telemetry_fresh ? telemetry : {},
        evaluated_at: Time.current.iso8601(6),
        limitations: "Agent-reported metrics are not independently verified; no live scan or backup restore test performed.",
        remote_execution_authorized: false
      }
    end
  end
end
