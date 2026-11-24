module ItServices
  class DeviceAssignment
    def self.call!(request:, device:, actor:)
      raise ArgumentError, "Super admin authorization required" unless actor&.role == "super_admin"
      raise ArgumentError, "Device is retired" if device.status == "retired"
      raise ArgumentError, "Device ownership is not verified" unless device.owner_id == request.user_id
      request.with_lock do
        request.update!(network_managed_device: device)
      end
      request
    end
  end
end
