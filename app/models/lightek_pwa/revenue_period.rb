module LightekPwa
  # Historical paid windows survive cancellation. Refunds are reviewed separately;
  # estimates are never silently converted into withdrawable money.
  class RevenuePeriod < ApplicationRecord
    self.table_name = 'lightek_pwa_revenue_periods'
    belongs_to :purchase
    validates :source_reference, uniqueness: true, presence: true
    validates :starts_at, :ends_at, presence: true
    validates :creator_share_bps, inclusion: {in: [8000]}
    validate { errors.add(:ends_at, 'must follow start') if starts_at && ends_at && ends_at <= starts_at }
  end
end
