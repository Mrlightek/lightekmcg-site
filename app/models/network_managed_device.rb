class NetworkManagedDevice < ApplicationRecord
  DEVICE_TYPES = %w[phone tablet router switch access_point computer server camera sensor smart_home iot other].freeze
  STATUSES = %w[registered active offline maintenance retired].freeze
  PROTOCOLS = %w[mdm agent ssh snmp mqtt http other].freeze

  validates :name, :identifier, presence: true
  validates :identifier, uniqueness: true
  validates :device_type, inclusion: { in: DEVICE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :management_protocol, inclusion: { in: PROTOCOLS }, allow_blank: true
end
