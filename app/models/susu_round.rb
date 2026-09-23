# frozen_string_literal: true

class SusuRound < ApplicationRecord
  STATUSES = %w[scheduled open funding processing funded paid_out defaulted cancelled].freeze

  belongs_to :susu_cycle
  belongs_to :recipient_membership, class_name: "SusuMembership"
  has_many :susu_contributions, dependent: :nullify

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :number, uniqueness: { scope: :susu_cycle_id }
  validates :status, inclusion: { in: STATUSES }

  def susu_group = susu_cycle.susu_group
  def settled_amount = susu_contributions.succeeded.sum(:amount)

  def refresh_collected_amount!
    update!(collected_amount: settled_amount)
  end

  def fully_funded?
    collected_amount.to_d >= expected_pot.to_d
  end

  def recipient = recipient_membership.user
end
