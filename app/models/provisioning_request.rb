class ProvisioningRequest < ApplicationRecord
  APPROVAL_STATUSES = %w[pending auto_approved approved rejected].freeze
  EXECUTION_STATUSES = %w[
    draft
    awaiting_provider
    awaiting_cost
    awaiting_approval
    ready
    queued
    provisioning
    succeeded
    failed
    cancelled
  ].freeze

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :subscription, class_name: "DymondBank::Subscription", optional: true
  belongs_to :subscription_plan, class_name: "DymondBank::SubscriptionPlan", optional: true
  belongs_to :subscription_infrastructure_entitlement, optional: true
  belongs_to :provisioning_profile, optional: true
  belongs_to :compute_policy, optional: true
  belongs_to :compute_provider, optional: true
  belongs_to :gatekeeper_operation, optional: true

  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :execution_status, inclusion: { in: EXECUTION_STATUSES }
  validates :requested_node_count, numericality: { only_integer: true, greater_than: 0 }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :needs_approval, -> { where(approval_status: "pending", execution_status: "awaiting_approval") }

  def approved?
    approval_status.in?(%w[auto_approved approved])
  end

  def executable?
    approved? && execution_status == "ready" && compute_provider.present?
  end
end
