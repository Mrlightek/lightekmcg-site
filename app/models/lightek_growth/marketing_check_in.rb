module LightekGrowth
  class MarketingCheckIn < ApplicationRecord
    self.table_name = 'lightek_growth_marketing_check_ins'
    belongs_to :marketing_kit, class_name: 'LightekGrowth::MarketingKit'
    belongs_to :actor, class_name: 'User'
    validates :day_index, inclusion: {in: 0..6}, uniqueness: {scope: :marketing_kit_id}
    validates :status, inclusion: {in: %w[completed skipped]}
    validates :note, presence: true, length: {maximum: 1000}
    validate { errors.add(:base, 'Check-ins are immutable') if persisted? && changed? }
    before_destroy { throw :abort }
  end
end
