# frozen_string_literal: true

class ItManagedDeviceIncident < ApplicationRecord
  belongs_to :network_managed_device
  belongs_to :owner, class_name: "User"

  STATUSES = %w[open resolved].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :finding_code, presence: true, length: { maximum: 100 }
  validates :first_observed_at, :last_observed_at, presence: true
  validates :observation_count, numericality: { only_integer: true, greater_than: 0 }
  validate :device_owner_matches

  scope :open_incidents, -> { where(status: "open") }

  def device_owner_matches
    return unless network_managed_device && owner
    errors.add(:owner, "must match device owner") unless network_managed_device.owner_id == owner.id
  end
end
