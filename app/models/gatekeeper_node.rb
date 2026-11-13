class GatekeeperNode < ApplicationRecord
  STATUSES = %w[unknown provisioning healthy degraded unreachable failed deleting delete_failed decommissioned].freeze

  has_many :gatekeeper_projects, dependent: :restrict_with_error
  has_many :gatekeeper_operations, dependent: :restrict_with_error

  belongs_to :compute_provider, optional: true
  belongs_to :provisioning_profile, optional: true
  belongs_to :compute_policy, optional: true
  belongs_to :owner, polymorphic: true, optional: true

  validates :name, presence: true, uniqueness: true
  validates :ip_address, :ssh_user, presence: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  after_commit do
    DirectorySyncJob.perform_later(owner_id) if owner_type == 'User' && status == 'healthy' && defined?(DirectorySyncJob)
  end
  validate do
    if persisted? && (will_save_change_to_owner_id? || will_save_change_to_owner_type?) && defined?(LightekIdentity::NodeBinding) && LightekIdentity::NodeBinding.table_exists? && LightekIdentity::NodeBinding.exists?(gatekeeper_node_id: id)
      errors.add(:owner, 'requires a reviewed domain offboarding before transferring a directory-bound server')
    end
  end

  def local?
    %w[127.0.0.1 ::1 localhost].include?(ip_address.to_s) ||
      ip_address.to_s == ENV["GATEKEEPER_LOCAL_NODE_IP"].to_s
  end

  def display_host
    hostname.presence || ip_address
  end
end
