# app/models/concerns/susuable.rb
module Susuable
  extend ActiveSupport::Concern

  included do
    has_many :susu_memberships, dependent: :destroy
    has_many :members, through: :susu_memberships, source: :user
    has_many :susu_contributions, dependent: :destroy

    enum :status, { draft: 0, active: 1, completed: 2 }, default: :draft

    validates :contribution_amount, numericality: { greater_than: 0 }
    validates :cycle_frequency, presence: true
  end

  def current_cycle_complete?
    susu_contributions.succeeded.where(cycle_number: current_cycle).count == members.count
  end

  def pending_contribution_for(user)
    susu_contributions.pending.find_by(user: user, cycle_number: current_cycle)
  end

  def contribution_for_current_cycle(user)
    susu_contributions.find_by(user: user, cycle_number: current_cycle)
  end

  def build_contribution_for_payment!(user)
    raise "Susu is not active" unless active?
    raise "Already contributed for this cycle" if contributed_for_current_cycle?(user)

    contribution = susu_contributions.find_or_initialize_by(user: user, cycle_number: current_cycle)
    contribution.amount = contribution_amount
    contribution.status = "pending" unless contribution.succeeded?
    contribution.failure_message = nil unless contribution.succeeded?
    contribution.save!
    contribution
  end

  # Kept for non-processor/manual settlement paths.
  def record_contribution!(user)
    contribution = build_contribution_for_payment!(user)
    contribution.payment_succeeded!(nil)
    contribution
  end

  def contributed_for_current_cycle?(user)
    susu_contributions.succeeded.exists?(user: user, cycle_number: current_cycle)
  end

  def current_payout_recipient
    susu_memberships.find_by(payout_position: current_cycle)&.user
  end

  def settle_contribution!(contribution)
    raise ArgumentError, "Contribution belongs to a different Susu" unless contribution.susu_group_id == id
    return contribution if contribution.succeeded?

    transaction do
      contribution.update!(status: "succeeded", paid_at: Time.current, failure_message: nil)
      distribute_payout! if current_cycle_complete?
    end

    contribution
  end

  private

  def distribute_payout!
    recipient = current_payout_recipient
    total_pot = contribution_amount * members.count

    # Payout rail will be connected here without reducing the recipient's pot.
    # Dymond's network revenue is earned when contributions are collected.

    if current_cycle >= members.count
      update!(status: :completed)
    else
      increment!(:current_cycle)
    end
  end
end
