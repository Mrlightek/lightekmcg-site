class GatekeeperInstallation < ApplicationRecord
  belongs_to :gatekeeper_node
  has_many :gatekeeper_update_targets, dependent: :restrict_with_error
  validates :domain, presence: true, uniqueness: true,
    format: {with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/}, length: {maximum: 253}
  validates :channel, inclusion: {in: %w[stable beta]}

  def eligible?
    node = gatekeeper_node
    enabled? && !node.local? && node.status != "decommissioned" &&
      node.metadata.to_h["role"] != "production" && !node.metadata.to_h["local_node"]
  end
end
