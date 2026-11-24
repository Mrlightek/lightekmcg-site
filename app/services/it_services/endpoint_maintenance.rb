# frozen_string_literal: true

module ItServices
  # Safe, auditable request lifecycle. Does not execute shell commands or
  # accept unverified repair claims from an endpoint.
  class EndpointMaintenance
    def self.approve!(device:, actor:, code:)
      raise ArgumentError, "Unsupported action" unless ItDeviceMaintenanceAction::ACTIONS.include?(code)
      raise ArgumentError, "Authorized IT operator required" unless actor&.persisted? &&
        actor.role == "super_admin" && LightekPeople::LifecycleAccess.active?(actor)
      device.with_lock do
        raise ArgumentError, "Customer monitoring consent required" unless device.owner_id.present? &&
          device.managed_monitoring_enabled? && device.enrolled_at.present? &&
          device.status == "active"
        ItDeviceMaintenanceAction.create!(
          network_managed_device: device, owner_id: device.owner_id, approved_by: actor,
          action_code: code, status: "approved", request_nonce: SecureRandom.hex(24),
          expires_at: 10.minutes.from_now
        )
      end
    end

    def self.pending_for!(device:)
      return [] unless device.owner_id.present? && device.managed_monitoring_enabled? &&
        device.enrolled_at.present? && device.status == "active"
      ItDeviceMaintenanceAction.where(network_managed_device: device, owner_id: device.owner_id,
        status: "approved").where("expires_at > ?", Time.current)
        .order(:id).limit(10).map do |action|
        { id: action.id, code: action.action_code, nonce: action.request_nonce,
          expires_at: action.expires_at.iso8601 }
      end
    end

    def self.report!(device:, action_id:, nonce:, result:)
      raise ArgumentError, "Invalid result" unless result.is_a?(Hash) &&
        result.keys.map(&:to_s).sort == ["observation", "status"] &&
        %w[ok warning unavailable].include?(result["status"] || result[:status]) &&
        (result["observation"] || result[:observation]).is_a?(String) &&
        (result["observation"] || result[:observation]).length <= 500
      device.with_lock do
        raise ArgumentError, "Consent revoked or device unavailable" unless device.owner_id.present? &&
          device.managed_monitoring_enabled? && device.enrolled_at.present? && device.status == "active"
        action = ItDeviceMaintenanceAction.where(network_managed_device: device,
          owner_id: device.owner_id).find(action_id)
        action.with_lock do
          raise ArgumentError, "Action not pending or expired" unless action.status == "approved" &&
            action.expires_at.future? && ActiveSupport::SecurityUtils.secure_compare(action.request_nonce, nonce.to_s)
          action.update!(status: "reported", reported_at: Time.current, result: result)
        end
        action
      end
    end
  end
end
