# frozen_string_literal: true

module ItServices
  module BetaDevice
    SUPPORT_FILES = %w[lightek_device_agent.py lightek_backup_restore.py lightek_live_restore.py
      lightek_native_patch.py lightek_macos_patch.py].freeze
    class Denied < StandardError; end

    def self.staging_host?(host)
      return false unless host.is_a?(String) && ENV["LIGHTEK_RELEASE_ASSURANCE_TARGET"] == "1" &&
        host == ENV["LIGHTEK_DEPLOYED_SITE_HOST"]

      host.match?(/\Abatch-d-[a-z0-9]+(?:-[a-z0-9]+)*\.staging\.(?:[a-z0-9-]+\.)+[a-z]{2,}\z/)
    end

    def self.tester?(user)
      user&.role == "client" && user.email_address.match?(/\Abeta-[1-9][0-9]*@example\.test\z/) &&
        user.has_attribute?(:staging_access_expires_at) && user.staging_access_expires_at&.future? &&
        user.access_active?
    end

    def self.identifier(user)
      "msp-beta-#{user.id}"
    end

    def self.find(user)
      NetworkManagedDevice.find_by(owner: user, identifier: identifier(user))
    end

    def self.issue!(user)
      user.with_lock do
        raise Denied unless tester?(user)

        device = NetworkManagedDevice.find_by(identifier: identifier(user))
        raise Denied if device && device.owner_id != user.id

        device ||= NetworkManagedDevice.create!(owner: user, identifier: identifier(user),
          name: "MSP beta test device", device_type: "computer", management_protocol: "agent", status: "registered")
        token = device.rotate_enrollment_token!
        device.update!(managed_monitoring_enabled: true)
        [device, token]
      end
    end

    def self.revoke!(user)
      user.with_lock do
        device = find(user)
        return unless device

        device.with_lock do
          device.rotate_enrollment_token!
          device.update!(enrollment_token_digest: nil, status: "retired")
        end
      end
    end
  end
end
