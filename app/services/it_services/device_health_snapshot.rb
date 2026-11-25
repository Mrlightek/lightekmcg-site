module ItServices
  class DeviceHealthSnapshot
    def self.call!(request:, actor:)
      raise ArgumentError, "Customer authorization required" unless actor&.id == request.user_id && actor&.persisted?
      consent = ItServiceDiagnosticConsent.find_by(it_service_request: request)
      raise ArgumentError, "Diagnostic consent required" unless consent&.active? && consent.granted_by_id == actor.id
      device = request.network_managed_device
      raise ArgumentError, "Verified customer device required" unless device && device.owner_id == actor.id
      raise ArgumentError, "Device is retired" if device.status == "retired"
      {
        device_name: device.name, device_type: device.device_type, status: device.status,
        management_protocol: device.management_protocol, os_version: device.os_version,
        enrolled_at: device.enrolled_at, last_seen_at: device.last_seen_at,
        heartbeat_stale: device.heartbeat_stale?,
        managed_posture: ManagedDevicePosture.evaluate(device: device, owner: actor)
      }
    end
  end
end
