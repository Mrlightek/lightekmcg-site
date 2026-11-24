# frozen_string_literal: true

module ItServices
  # Reconciles observed device-health findings into deduplicated incidents.
  # Read-only against endpoints; never starts remediation or assumes coverage.
  # Each device is locked to serialize concurrent sweeps.
  class ManagedFleetIncidents
    def self.reconcile!(device:, owner:)
      raise ArgumentError, "Owner-scoped review required" unless owner&.persisted? &&
        device.owner_id.present? && device.owner_id == owner.id
      device.with_lock do
        return unless device.managed_monitoring_enabled? && LightekPeople::LifecycleAccess.active?(owner)

        posture = ManagedDevicePosture.evaluate(device: device, owner: owner)
        now = Time.current
        observed = posture.fetch(:findings)
        existing = ItManagedDeviceIncident.open_incidents.where(
          network_managed_device_id: device.id, owner_id: owner.id).index_by(&:finding_code)
        opened = []
        updated = []
        resolved = []
        observed.each do |code|
          if incident = existing.delete(code)
            incident.update!(last_observed_at: now, observation_count: incident.observation_count + 1)
            updated << incident.id
          else
            incident = ItManagedDeviceIncident.create!(
              network_managed_device: device, owner: owner, finding_code: code,
              status: "open", first_observed_at: now, last_observed_at: now)
            opened << incident.id
          end
        end
        existing.each_value do |incident|
          # Missing telemetry or a disconnected device cannot prove recovery.
          # Close an incident only after fresh evidence explicitly covers it.
          next unless recovery_verified?(code: incident.finding_code, device: device, posture: posture)
          incident.update!(status: "resolved", resolved_at: now, last_observed_at: now)
          resolved << incident.id
        end
        { device_id: device.id, owner_id: owner.id, opened: opened,
          updated: updated, resolved: resolved, findings: observed,
          remote_execution_authorized: false }
      end
    end

    def self.recovery_verified?(code:, device:, posture:)
      return false unless device.status == "active" && device.enrolled_at.present? &&
        device.last_seen_at.present? && !device.heartbeat_stale?
      case code
      when "not_enrolled", "not_active", "heartbeat_missing", "heartbeat_stale"
        true
      when "endpoint_protection_alert"
        posture[:telemetry_fresh] && posture[:reported_telemetry]["endpoint_protection"] == "healthy"
      when "backup_failed"
        # Endpoint self-report is not evidence of a successful restore.
        false
      when "backup_recovery_test_failed"
        posture[:backup_sample_status] == "verified"
      when "staged_restore_failed"
        posture[:staged_restore_status] == "verified"
      when "patch_deployment_failed"
        posture[:patch_deployment_status] == "verified"
      when "patches_available"
        # Package inventories alone do not establish OS patch compliance.
        false
      when "disk_pressure"
        posture[:telemetry_fresh] && posture[:reported_telemetry]["disk_percent"].is_a?(Numeric) &&
          posture[:reported_telemetry]["disk_percent"] < 90
      when "telemetry_missing_or_stale"
        posture[:telemetry_fresh]
      when "retired"
        false
      else
        false
      end
    end

    def self.review_owner!(owner:, limit: 250)
      raise ArgumentError, "Active owner required" unless owner&.persisted? && LightekPeople::LifecycleAccess.active?(owner)
      raise ArgumentError, "Invalid limit" unless limit.is_a?(Integer) && limit.between?(1, 250)
      NetworkManagedDevice.where(owner_id: owner.id, managed_monitoring_enabled: true)
        .where.not(enrolled_at: nil).order(:id).limit(limit).filter_map do |device|
        reconcile!(device: device, owner: owner)
      end
    end
  end
end
