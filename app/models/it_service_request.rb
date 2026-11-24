class ItServiceRequest < ApplicationRecord
  SERVICES = {
    "malware_removal" => "Virus & malware removal",
    "optimization" => "System optimization",
    "computer_repair" => "Computer repair",
    "network_support" => "Network troubleshooting",
    "backup_recovery" => "Backup & recovery assessment",
    "managed_it" => "Managed IT support"
  }.freeze
  MODES = %w[remote onsite].freeze
  STATUSES = %w[requested triaged scheduled in_progress awaiting_customer resolved cancelled].freeze

  belongs_to :technician, class_name: "User", optional: true
  belongs_to :reservation, class_name: "LightekReservations::Reservation", optional: true
  belongs_to :network_managed_device, optional: true
  validate :reservation_belongs_to_customer

  def reservation_belongs_to_customer
    return unless reservation
    errors.add(:reservation, "must belong to the customer") unless user_id.present? && reservation.customer_id == user_id
    errors.add(:reservation, "must be a service reservation") unless reservation.resource&.kind == "service"
  end
  belongs_to :user
  validate :device_belongs_to_customer

  def device_belongs_to_customer
    return if network_managed_device.nil?
    errors.add(:network_managed_device, "must belong to the customer") unless network_managed_device.owner_id == user_id && user_id.present?
  end
  validates :user, presence: true
  validates :service_code, inclusion: { in: SERVICES.keys }
  validates :delivery_mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :description, presence: true, length: { maximum: 4000 }
  validates :service_location, presence: true, if: -> { delivery_mode == "onsite" }
  validates :service_location, length: { maximum: 1000 }, allow_blank: true
  validates :device_platform, length: { maximum: 100 }, allow_blank: true
end
