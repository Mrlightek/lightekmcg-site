# app/models/concerns/susuable.rb
module Susuable
  extend ActiveSupport::Concern

  included do
    has_many :susu_memberships, dependent: :destroy
    has_many :members, through: :susu_memberships, source: :user
    has_many :susu_contributions, dependent: :destroy

    enum :status, { draft: 0, active: 1, completed: 2 }, default: :draft

    validates :contribution_amount, numericality: { greater_than: 0 }
    validates :cycle_frequency, presence: true, inclusion: { in: %w[weekly biweekly monthly] }
  end

  def organizer?(user)
    organizer_id == user&.id
  end


  # Planned pot while the Susu is still being assembled.
  def projected_cycle_pot
    contribution_amount * target_member_count.to_i
  end

  # Full pot for an active cycle based on the actual member roster.
  # This is the amount due for the cycle, not the amount collected so far.
  def cycle_pot
    contribution_amount * members.count
  end

  # Only successfully settled contributions count as collected money.
  def collected_for_current_cycle
    susu_contributions
      .succeeded
      .where(cycle_number: current_cycle)
      .sum(:amount)
  end

  def cycle_progress_percent
    pot = cycle_pot.to_d
    return 0 if pot <= 0

    ((collected_for_current_cycle.to_d / pot) * 100)
      .clamp(0, 100)
  end

  def next_payout_position
    (susu_memberships.maximum(:payout_position) || 0) + 1
  end

  def ready_to_activate?
    return false unless draft?
    return false unless members.count == target_member_count.to_i

    susu_memberships.order(:payout_position).pluck(:payout_position) == (1..target_member_count.to_i).to_a
  end

  def payment_state_for(user)
    contribution = contribution_for_current_cycle(user)
    return :due unless contribution

    contribution.status.to_sym
  end

  def current_cycle_complete?
    round_number = respond_to?(:current_round_number) ? current_round_number : 1

    susu_contributions
      .succeeded
      .where(cycle_number: current_cycle, round_number: round_number)
      .count == members.count
  end

  def pending_contribution_for(user)
    round_number = respond_to?(:current_round_number) ? current_round_number : 1

    susu_contributions.pending.find_by(
      user: user,
      cycle_number: current_cycle,
      round_number: round_number
    )
  end

  def contribution_for_current_cycle(user)
    round_number = respond_to?(:current_round_number) ? current_round_number : 1

    susu_contributions.find_by(
      user: user,
      cycle_number: current_cycle,
      round_number: round_number
    )
  end

  def build_contribution_for_payment!(user)
    raise "Susu is not active" unless active?
    raise "Already contributed for this round" if contributed_for_current_cycle?(user)

    membership = susu_memberships.find_by!(user: user)
    round = respond_to?(:current_round_record) ? current_round_record : nil

    contribution = susu_contributions.find_or_initialize_by(
      user: user,
      cycle_number: current_cycle,
      round_number: respond_to?(:current_round_number) ? current_round_number : 1
    )

    contribution.amount = contribution_amount
    contribution.status = "pending" unless contribution.succeeded?
    contribution.failure_message = nil unless contribution.succeeded?
    contribution.susu_membership = membership if contribution.respond_to?(:susu_membership=)
    contribution.susu_round = round if round && contribution.respond_to?(:susu_round=)
    contribution.save!
    contribution
  end

  def record_contribution!(user)
    contribution = build_contribution_for_payment!(user)
    contribution.payment_succeeded!(nil)
    contribution
  end

  def contributed_for_current_cycle?(user)
    round_number = respond_to?(:current_round_number) ? current_round_number : 1

    susu_contributions.succeeded.exists?(
      user: user,
      cycle_number: current_cycle,
      round_number: round_number
    )
  end

  def current_payout_recipient
    position = respond_to?(:current_round_number) ? current_round_number : current_cycle
    susu_memberships.find_by(payout_position: position)&.user
  end

  def settle_contribution!(contribution)
    if respond_to?(:current_round_record) && current_round_record
      return Susu::LifecycleService.settle_contribution!(contribution)
    end

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
