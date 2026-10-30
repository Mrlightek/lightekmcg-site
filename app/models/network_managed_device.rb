require "digest"
require "securerandom"
require "ipaddr"
class NetworkManagedDevice < ApplicationRecord
  DEVICE_TYPES = %w[phone tablet router switch access_point computer server camera sensor smart_home iot other].freeze
  STATUSES = %w[registered active offline maintenance retired].freeze
  PROTOCOLS = %w[mdm agent ssh snmp mqtt http other].freeze

  validates :name, :identifier, presence: true
  validate :validate_network_address
  validates :identifier, uniqueness: true
  validates :device_type, inclusion: { in: DEVICE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :management_protocol, inclusion: { in: PROTOCOLS }, allow_blank: true
  HEARTBEAT_TIMEOUT = 5.minutes

  scope :stale_heartbeats, -> { where(status: "active").where("last_seen_at < ?", HEARTBEAT_TIMEOUT.ago) }

  def heartbeat_stale?
    status == "active" && last_seen_at.present? && last_seen_at < HEARTBEAT_TIMEOUT.ago
  end

  def mark_offline_if_stale!
    with_lock do
      return false unless heartbeat_stale?
      update!(status: "offline")
      true
    end
  end

  def rotate_enrollment_token!
    token = SecureRandom.hex(32)
    update!(enrollment_token_digest: Digest::SHA256.hexdigest(token), enrolled_at: nil,
      last_seen_at: nil, last_heartbeat_ip: nil, status: "registered")
    token
  end

  def authenticate_enrollment_token?(token)
    return false if enrollment_token_digest.blank? || token.blank?
    candidate = Digest::SHA256.hexdigest(token.to_s)
    ActiveSupport::SecurityUtils.secure_compare(enrollment_token_digest, candidate)
  end

  private

  def validate_network_address
    return if ip_address.blank?
    IPAddr.new(ip_address)
  rescue IPAddr::InvalidAddressError
    errors.add(:ip_address, "must be a valid IPv4 or IPv6 address")
  end
end
