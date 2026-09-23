# frozen_string_literal: true

class SusuMatchPreference < ApplicationRecord
  STATUSES = %w[open proposed matched paused closed].freeze
  MODES = %w[suggestions matched_circle hybrid].freeze
  FREQUENCIES = %w[weekly biweekly monthly].freeze

  belongs_to :user

  validates :contribution_amount, numericality: { greater_than: 0 }
  validates :cycle_frequency, inclusion: { in: FREQUENCIES }
  validates :desired_payout, numericality: { greater_than: 0 }
  validates :desired_member_count, numericality: { only_integer: true, greater_than_or_equal_to: 2 }
  validates :matching_mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
end
