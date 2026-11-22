# frozen_string_literal: true

module LightekGrowth
  class DemoExposure < ApplicationRecord
    self.table_name = 'lightek_growth_demo_exposures'
    belongs_to :showcase, class_name: 'LightekGrowth::FeatureShowcase'
    belongs_to :visit, class_name: 'LightekGrowth::Visit'
    validates :variant, inclusion: { in: %w[control challenger] }
  end
end
