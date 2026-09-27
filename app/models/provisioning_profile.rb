class ProvisioningProfile < ApplicationRecord
  validates :name, :slug, :purpose, :os_image, presence: true
  validates :slug, uniqueness: true
  scope :active, -> { where(active: true) }

  has_many :gatekeeper_nodes, dependent: :restrict_with_error
  has_many :subscription_infrastructure_entitlements, dependent: :restrict_with_error
end
