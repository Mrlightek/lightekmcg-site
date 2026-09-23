# frozen_string_literal: true

class SusuCommitment < ApplicationRecord
  STATUSES = %w[pending active completed delinquent defaulted cancelled].freeze

  belongs_to :susu_membership
  belongs_to :susu_cycle, optional: true

  validates :contribution_amount, numericality: { greater_than: 0 }
  validates :rounds_committed, numericality: { only_integer: true, greater_than: 0 }
  validates :remaining_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :terms_version, presence: true

  scope :open, -> { where(status: %w[pending active delinquent]) }

  def accept!
    update!(status: "active", accepted_at: Time.current)
  end

  def apply_settlement!(amount)
    remaining = [remaining_amount.to_d - amount.to_d, 0.to_d].max
    update!(
      remaining_amount: remaining,
      status: remaining.zero? ? "completed" : status
    )
  end
end
