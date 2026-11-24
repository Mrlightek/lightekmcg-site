class ItDeviceMaintenanceAction < ApplicationRecord
  ACTIONS = %w[refresh_inventory check_patch_status check_backup_status check_endpoint_protection].freeze
  STATUSES = %w[approved reported expired cancelled].freeze
  belongs_to :network_managed_device
  belongs_to :owner, class_name: "User"
  belongs_to :approved_by, class_name: "User"
  validates :action_code, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :request_nonce, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :owner_matches_device

  def owner_matches_device
    errors.add(:owner, "must match device owner") if network_managed_device &&
      owner && network_managed_device.owner_id != owner.id
  end
end
