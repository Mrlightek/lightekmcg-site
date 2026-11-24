# frozen_string_literal: true

module ItServices
  # Safe, auditable request lifecycle. Does not execute shell commands or
  # accept unverified repair claims from an endpoint.
  class EndpointMaintenance
    WINDOW_LENGTH = 10.minutes
    MAX_SCHEDULE_AHEAD = 30.days

    def self.approve!(device:, actor:, code:, scheduled_at: nil, expected_recovery_digest: nil, patch_target: nil)
      raise ArgumentError, "Unsupported action" unless ItDeviceMaintenanceAction::ACTIONS.include?(code)
      require_operator!(actor)
      recovery_check = [ItDeviceMaintenanceAction::RECOVERY_CHECK, ItDeviceMaintenanceAction::STAGED_RESTORE, ItDeviceMaintenanceAction::LIVE_RESTORE].include?(code)
      if recovery_check && (scheduled_at.blank? || !expected_recovery_digest.is_a?(String))
        raise ArgumentError, "Recovery verification requires a scheduled time and an expected SHA-256 digest"
      end
      patch_format = ItDeviceMaintenanceAction::PATCH_TARGETS[code]
      if patch_format && (scheduled_at.blank? || !patch_target.is_a?(String) ||
          !patch_format.match?(patch_target))
        raise ArgumentError, "Patch deployment requires a scheduled time and a valid exact target for the platform"
      end
      device.with_lock do
        raise ArgumentError, "Customer monitoring consent required" unless available?(device)
        now = Time.current
        starts_at = scheduled_at.present? ? parse_schedule(scheduled_at) : now
        raise ArgumentError, "Choose a time within the next 30 days" unless
          starts_at.between?(now, now + MAX_SCHEDULE_AHEAD)
        ItDeviceMaintenanceAction.create!(
          network_managed_device: device, owner_id: device.owner_id, approved_by: actor,
          action_code: code, status: "approved", request_nonce: SecureRandom.hex(24),
          starts_at: starts_at, expires_at: starts_at + WINDOW_LENGTH,
          patch_target: (patch_target if patch_format),
          expected_recovery_digest: (expected_recovery_digest.strip.downcase if recovery_check)
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
        raise ArgumentError, "Action can no longer be cancelled" unless action.cancellable?
        action.update!(status: "cancelled")
        action
      end
    end

    def self.consent!(device:, action_id:, actor:, code: ItDeviceMaintenanceAction::RECOVERY_CHECK)
      device.with_lock do
        raise ActiveRecord::RecordNotFound unless actor&.persisted? && actor.id == device.owner_id
        raise ArgumentError, "Customer monitoring consent required" unless available?(device)
        action = owned_actions(device).find(action_id)
        unless action.display_status == "awaiting_customer_consent" && action.action_code == code
          raise ArgumentError, "Maintenance action is no longer awaiting consent"
        end
        action.update!(owner_consented_at: Time.current)
        action
      end
    end

    def self.pending_for!(device:, now: Time.current)
      return [] unless available?(device)

      owned_actions(device).where(status: "approved").where("expires_at > ?", now)
        .where("starts_at IS NULL OR starts_at <= ?", now)
        .where(claimed_at: nil)
        .where("action_code NOT IN (?) OR owner_consented_at IS NOT NULL", ItDeviceMaintenanceAction::CONSENT_REQUIRED)
        .order(:expires_at, :id).limit(10).map do |action|
        { id: action.id, code: action.action_code, nonce: action.request_nonce,
          expires_at: action.expires_at.iso8601 }
      end
    end

    def self.claim!(device:, action_id:, nonce:)
      device.with_lock do
        raise ArgumentError, "Consent revoked or device unavailable" unless available?(device)
        action = owned_actions(device).find(action_id)
        unless action.consent_required? && action.display_status == "awaiting_report" &&
          ActiveSupport::SecurityUtils.secure_compare(action.request_nonce, nonce.to_s)
          raise ArgumentError, "Maintenance action cannot be claimed"
        end
        action.update!(claimed_at: Time.current)
        action
      end
    end

    def self.report!(device:, action_id:, nonce:, result:)
      raise ArgumentError, "Invalid result" unless result.is_a?(Hash)
      device.with_lock do
        raise ArgumentError, "Consent revoked or device unavailable" unless available?(device)
        action = owned_actions(device).find(action_id)
        expected_status = action.consent_required? ? "running" : "awaiting_report"
        raise ArgumentError, "Action not pending or expired" unless action.display_status == expected_status &&
          ActiveSupport::SecurityUtils.secure_compare(action.request_nonce, nonce.to_s)
        evidence = case action.action_code
        when ItDeviceMaintenanceAction::RECOVERY_CHECK then verified_recovery_result(action, result)
        when ItDeviceMaintenanceAction::STAGED_RESTORE then staged_restore_result(action, result)
        when ItDeviceMaintenanceAction::LIVE_RESTORE then live_restore_result(action, result)
        when *ItDeviceMaintenanceAction::PATCH_TARGETS.keys then verified_patch_result(action, result)
        else check_result(action, result)
        end
        action.update!(status: "reported", reported_at: Time.current, result: evidence)
        action
      end
    end

    def self.check_result(action, result)
      data = result.stringify_keys
      keys = %w[observation status]
      if action.action_code == "check_patch_status" && data.key?("available_update_count")
        count = data["available_update_count"]
        unless count.is_a?(Integer) && count.between?(0, 999_999) &&
          data["status"] == (count.positive? ? "warning" : "ok")
          raise ArgumentError, "Invalid patch inventory evidence"
        end
        keys.unshift("available_update_count")
      end
      raise ArgumentError, "Invalid result" unless result.size == keys.size && data.keys.sort == keys &&
        %w[ok warning unavailable].include?(data["status"]) && data["observation"].is_a?(String) &&
        data["observation"].length <= 500

      data
    end

    def self.verified_recovery_result(action, result)
      data = result.stringify_keys
      if result.size == 1 && data == { "status" => "unavailable" }
        return { "status" => "unavailable", "observation" => "The endpoint could not read the configured backup sample." }
      end
      digest = data["sha256"]
      unless result.size == 2 && data.keys.sort == %w[sha256 status] && data["status"] == "restored" &&
        digest.is_a?(String) && ItDeviceMaintenanceAction::RECOVERY_DIGEST.match?(digest)
        raise ArgumentError, "Invalid recovery evidence"
      end

      matched = ActiveSupport::SecurityUtils.secure_compare(action.expected_recovery_digest, digest)
      { "status" => matched ? "verified" : "mismatch", "sha256" => digest,
        "observation" => matched ? "Restored backup sample matched the expected digest." : "Restored backup sample did not match the expected digest." }
    end

    def self.staged_restore_result(action, result)
      data = result.stringify_keys
      if result.size == 1 && %w[failed unavailable mismatch].include?(data["status"])
        return { "status" => data["status"], "observation" => "A verified staged restore was not produced." }
      end
      if result.size != 5 || data.keys.sort != %w[byte_count file_count sha256 staging_reference status] ||
          data["status"] != "staged" || data["sha256"] != action.expected_recovery_digest ||
          !data["file_count"].is_a?(Integer) || !data["file_count"].between?(1, 1024) ||
          !data["byte_count"].is_a?(Integer) || !data["byte_count"].between?(0, 512.megabytes) ||
          !data["staging_reference"].is_a?(String) || !data["staging_reference"].match?(/\Alightek-restore-[0-9a-f]{32}\z/)
        raise ArgumentError, "Invalid staged recovery evidence"
      end

      data.merge("status" => "verified",
        "observation" => "The endpoint restored and read back #{data['file_count']} files in #{data['staging_reference']}.")
    end

    def self.live_restore_result(action, result)
      data = result.stringify_keys
      if result.size == 1 && %w[failed unavailable mismatch rolled_back].include?(data["status"])
        return { "status" => data["status"], "observation" => "The verified backup could not be placed into service." }
      end
      reference = data["rollback_reference"]
      unless result.size == 3 && data.keys.sort == %w[rollback_reference sha256 status] &&
          data["status"] == "activated" && data["sha256"] == action.expected_recovery_digest &&
          reference.is_a?(String) && reference.match?(/\Alightek-restore-[0-9a-f]{32}\z/)
        raise ArgumentError, "Invalid live recovery evidence"
      end

      data.merge("status" => "verified", "observation" => "Restored files are active. Previous files retained as #{reference}.")
    end

    def self.verified_patch_result(action, result)
      data = result.stringify_keys
      if result.size == 1 && %w[failed unavailable pending_restart].include?(data["status"])
        observation = if data["status"] == "pending_restart"
          "Complete the authorized restart and verify the exact target again."
        else
          "The installed patch could not be confirmed."
        end
        return { "status" => data["status"], "observation" => observation }
      end
      unless result.size == 2 && data.keys.sort == %w[status target] && data["status"] == "installed" &&
          data["target"] == action.patch_target
        raise ArgumentError, "Patch result does not match the approved package and version"
      end

      { "status" => "verified", "target" => action.patch_target,
        "observation" => "The endpoint package database confirmed the approved version." }
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
    private_class_method :available?, :owned_actions, :require_operator!, :parse_schedule, :check_result,
      :verified_recovery_result, :verified_patch_result, :staged_restore_result, :live_restore_result
  end
end
