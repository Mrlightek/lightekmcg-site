class ComputePolicy < ApplicationRecord
  belongs_to :preferred_provider, class_name: "ComputeProvider", optional: true
  belongs_to :fallback_provider, class_name: "ComputeProvider", optional: true

  has_many :gatekeeper_nodes, dependent: :restrict_with_error
  has_many :subscription_infrastructure_entitlements, dependent: :restrict_with_error

  validates :name, :slug, :purpose, presence: true
  validates :slug, uniqueness: true
  scope :active, -> { where(active: true) }

  def approval_required_for?(monthly_cost_cents)
    automatic_approval_ceiling_cents.blank? || monthly_cost_cents.to_i > automatic_approval_ceiling_cents
  end
end
