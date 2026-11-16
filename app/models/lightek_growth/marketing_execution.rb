module LightekGrowth
  class MarketingExecution < ApplicationRecord
    self.table_name = 'lightek_growth_marketing_executions'
    belongs_to :marketing_kit, class_name: 'LightekGrowth::MarketingKit'
    belongs_to :actor, class_name: 'User'
    belongs_to :goal, class_name: 'NevaehGoal'
    validates :marketing_kit_id, uniqueness: true
  end
end
