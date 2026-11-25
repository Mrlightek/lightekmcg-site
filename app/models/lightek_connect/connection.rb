require "digest"
module LightekConnect
  class Connection < ApplicationRecord
    self.table_name = "lightek_connect_connections"
    belongs_to :user
    has_many :grants, class_name: "LightekConnect::Grant", dependent: :destroy
    EXTERNAL_PLATFORMS = %w[wordpress shopify].freeze
    validates :platform, inclusion: {in: EXTERNAL_PLATFORMS + %w[dashboard]}
    validates :label, presence: true, length: {maximum: 120}
    def self.digest(value) = Digest::SHA256.hexdigest(value.to_s)
    def self.issue!(user:, platform:, label:)
      raise ArgumentError, "Choose WordPress or Shopify" unless EXTERNAL_PLATFORMS.include?(platform)
      raise Gatekeeper::Hosting::Access::Denied, "Agency access required" unless (user.role.in?(%w[white_label super_admin]) && (!defined?(LightekPeople::LifecycleAccess) || LightekPeople::LifecycleAccess.agency_ready?(user)))
      code = SecureRandom.hex(32)
      connection = create!(user: user, platform: platform, label: label, code_digest: digest(code), code_expires_at: 10.minutes.from_now)
      [connection, code]
    end
    def self.redeem!(code:, platform:, identity:)
      raise ArgumentError, "Choose WordPress or Shopify" unless EXTERNAL_PLATFORMS.include?(platform)
      raise ArgumentError, "Invalid connection code" unless code.to_s.match?(/\A[0-9a-f]{64}\z/)
      connection = find_by!(code_digest: digest(code), platform: platform)
      token = SecureRandom.hex(32)
      connection.with_lock do
        raise Gatekeeper::Hosting::Access::Denied, "Connection code expired or already used" unless connection.code_digest == digest(code) && connection.code_expires_at > Time.current && connection.revoked_at.nil?
        raise Gatekeeper::Hosting::Access::Denied, "Agency access removed" unless (connection.user.role.in?(%w[white_label super_admin]) && (!defined?(LightekPeople::LifecycleAccess) || LightekPeople::LifecycleAccess.agency_ready?(connection.user)))
        connection.update!(code_digest: nil, code_expires_at: nil, token_digest: digest(token), external_identity: identity)
        Event.record!(connection, "connected")
      end
      [connection, token]
    end
    def self.authenticate(token)
      return unless token.to_s.match?(/\A[0-9a-f]{64}\z/)
      connection = find_by(token_digest: digest(token), revoked_at: nil)
      connection if connection&.user&.role.in?(%w[white_label super_admin]) && (!defined?(LightekPeople::LifecycleAccess) || LightekPeople::LifecycleAccess.agency_ready?(connection.user))
    end
    def revoke!
      with_lock do
        update!(revoked_at: Time.current, code_digest: nil, token_digest: nil)
        Event.record!(self, "revoked")
      end
    end
  end
end
