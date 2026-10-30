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
  private

  def validate_network_address
    return if ip_address.blank?
    IPAddr.new(ip_address)
  rescue IPAddr::InvalidAddressError
    errors.add(:ip_address, "must be a valid IPv4 or IPv6 address")
  end
end
