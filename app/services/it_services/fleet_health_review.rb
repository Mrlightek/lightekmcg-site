# frozen_string_literal: true

module ItServices
  # Tenant/owner-scoped fleet review. No device access, command execution or
  # automatic repair; callers can use findings to initiate approved incident work.
  class FleetHealthReview
    def self.call!(owner:, limit: 250)
      raise ArgumentError, "Active device owner required" unless owner&.persisted? && owner.access_active?
      raise ArgumentError, "Invalid fleet review limit" unless limit.is_a?(Integer) && limit.between?(1, 250)
      devices = NetworkManagedDevice.where(owner_id: owner.id).order(:id).limit(limit)
      reports = devices.map { |device| ManagedDevicePosture.evaluate(device: device, owner: owner) }
      {
        owner_id: owner.id,
        standard: "lightek_managed_device_v1",
        reviewed_count: reports.size,
        attention_count: reports.count { |report| report[:status] == "attention_required" },
        devices: reports,
        limitations: "Read-only enrollment and connectivity review; no scans or repairs performed.",
        reviewed_at: Time.current.iso8601(6)
      }
    end
  end
end
