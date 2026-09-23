# frozen_string_literal: true

module SusuLifecycle
  extend ActiveSupport::Concern

  included do
    has_many :susu_cycles, dependent: :destroy
    has_many :susu_rounds, through: :susu_cycles
  end

  def current_cycle_record
    susu_cycles.where(status: "active").order(number: :desc).first ||
      susu_cycles.order(number: :desc).first
  end

  def current_round_record
    cycle = current_cycle_record
    return unless cycle

    cycle.susu_rounds
         .where(status: %w[open funding processing funded])
         .order(:number)
         .first
  end

  def payout_amount
    contribution_amount * members.count
  end

  def cycle_total_volume
    payout_amount * members.count
  end

  def rounds_per_cycle
    members.count
  end

  def projected_payout_amount
    contribution_amount * target_member_count.to_i
  end

  def projected_cycle_total_volume
    projected_payout_amount * target_member_count.to_i
  end

  def duration_label
    count = target_member_count.to_i
    return "Not configured" if count <= 0

    case cycle_frequency
    when "weekly" then "#{count} #{count == 1 ? 'week' : 'weeks'}"
    when "biweekly" then "#{count * 2} weeks"
    when "monthly" then "#{count} #{count == 1 ? 'month' : 'months'}"
    else "#{count} rounds"
    end
  end

  def outstanding_commitment_for(user)
    membership = susu_memberships.find_by(user: user)
    membership&.susu_commitments&.where(status: %w[pending active delinquent])&.order(created_at: :desc)&.first
  end
end
