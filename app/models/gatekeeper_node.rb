class GatekeeperNode < ApplicationRecord
  STATUSES = %w[unknown provisioning healthy degraded unreachable failed].freeze

  has_many :gatekeeper_projects, dependent: :restrict_with_error
  has_many :gatekeeper_operations, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :ip_address, :ssh_user, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  def local?
    %w[127.0.0.1 ::1 localhost].include?(ip_address.to_s) ||
      ip_address.to_s == ENV["GATEKEEPER_LOCAL_NODE_IP"].to_s
  end

  def display_host
    hostname.presence || ip_address
  end
end
