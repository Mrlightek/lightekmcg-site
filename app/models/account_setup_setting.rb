# frozen_string_literal: true

class AccountSetupSetting < ApplicationRecord
  LIFETIMES = {
    20 => "20 minutes",
    60 => "1 hour",
    360 => "6 hours",
    1_440 => "24 hours",
    2_880 => "48 hours",
    4_320 => "72 hours",
    10_080 => "7 days"
  }.freeze
  DEFAULT_MINUTES = 2_880

  validates :link_minutes, inclusion: { in: LIFETIMES.keys }

  def self.link_minutes
    find_by(id: 1)&.link_minutes || DEFAULT_MINUTES
  end
end
