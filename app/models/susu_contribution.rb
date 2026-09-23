class SusuContribution < ApplicationRecord
  belongs_to :susu_group
  belongs_to :user
  belongs_to :susu_round, optional: true
  belongs_to :susu_membership, optional: true

  has_one :payment_transaction,
          as: :payable,
          class_name: "DymondBank::Transaction",
          dependent: :nullify

  STATUSES = %w[pending processing succeeded failed grace_period retrying delinquent defaulted].freeze

  validates :amount, numericality: { greater_than: 0 }
  validates :cycle_number, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: {
    scope: [:susu_group_id, :cycle_number],
    message: "has already contributed for this cycle"
  }

  scope :pending, -> { where(status: "pending") }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :failed, -> { where(status: "failed") }

  def pending? = status == "pending"
  def succeeded? = status == "succeeded"
  def failed? = status == "failed"

  def payment_succeeded!(transaction)
    susu_group.settle_contribution!(self)
  end

  def payment_failed!(_transaction, message: nil)
    update!(status: "failed", failure_message: message)
  end
end
