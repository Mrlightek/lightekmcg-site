# frozen_string_literal: true

module ItServices
  # Safe, auditable request lifecycle. Does not execute shell commands or
  # accept unverified repair claims from an endpoint.
  class EndpointMaintenance
    WINDOW_LENGTH = 10.minutes
    MAX_SCHEDULE_AHEAD = 30.days

    def self.approve!(device:, actor:, code:, scheduled_at: nil)
      raise ArgumentError, "Unsupported action" unless ItDeviceMaintenanceAction::ACTIONS.include?(code)
      require_operator!(actor)
      device.with_lock do
        raise ArgumentError, "Customer monitoring consent required" unless available?(device)
        now = Time.current
        starts_at = scheduled_at.present? ? parse_schedule(scheduled_at) : now
        raise ArgumentError, "Choose a time within the next 30 days" unless
          starts_at.between?(now, now + MAX_SCHEDULE_AHEAD)
        ItDeviceMaintenanceAction.create!(
          network_managed_device: device, owner_id: device.owner_id, approved_by: actor,
          action_code: code, status: "approved", request_nonce: SecureRandom.hex(24),
          starts_at: starts_at, expires_at: starts_at + WINDOW_LENGTH
        )
      end
    end

    def self.cancel!(device:, action_id:, actor:, owner_only: false)
      device.with_lock do
        owner_authorized = actor&.persisted? && actor.id == device.owner_id &&
          LightekPeople::LifecycleAccess.active?(actor)
        if owner_only
          raise ActiveRecord::RecordNotFound unless owner_authorized
        else
          require_operator!(actor)
        end
        action = owned_actions(device).find(action_id)
        raise ArgumentError, "Action is no longer awaiting a report" unless
          %w[scheduled awaiting_report].include?(action.display_status)
        action.update!(status: "cancelled")
        action
      end
    end

    def self.pending_for!(device:, now: Time.current)
      return [] unless available?(device)

      owned_actions(device).where(status: "approved").where("expires_at > ?", now)
        .where("starts_at IS NULL OR starts_at <= ?", now)
        .order(:expires_at, :id).limit(10).map do |action|
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
        raise ArgumentError, "Consent revoked or device unavailable" unless available?(device)
        action = owned_actions(device).find(action_id)
        action.with_lock do
          raise ArgumentError, "Action not pending or expired" unless action.display_status == "awaiting_report" &&
            ActiveSupport::SecurityUtils.secure_compare(action.request_nonce, nonce.to_s)
          action.update!(status: "reported", reported_at: Time.current, result: result)
        end
        action
      end
    end

    def self.available?(device)
      device.owner_id.present? && device.managed_monitoring_enabled? && device.enrolled_at.present? &&
        device.status == "active" && LightekPeople::LifecycleAccess.active?(device.owner)
    end

    def self.owned_actions(device)
      ItDeviceMaintenanceAction.where(network_managed_device: device, owner_id: device.owner_id)
    end

    def self.require_operator!(actor)
      raise ArgumentError, "Authorized IT operator required" unless actor&.persisted? &&
        actor.role == "super_admin" && LightekPeople::LifecycleAccess.active?(actor)
    end

    def self.parse_schedule(value)
      unless value.is_a?(String) && value.length <= 40 && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
        raise ArgumentError, "Enter an ISO 8601 time with a UTC offset"
      end

      Time.iso8601(value)
    end
    private_class_method :available?, :owned_actions, :require_operator!, :parse_schedule
  end
end
