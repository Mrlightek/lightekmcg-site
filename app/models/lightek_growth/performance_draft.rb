module LightekGrowth
  class PerformanceDraft < ApplicationRecord
    self.table_name = 'lightek_growth_performance_drafts'
    belongs_to :review, class_name: 'LightekGrowth::PerformanceReview'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :created_by, class_name: 'User'
    validate do
      errors.add(:base, 'Draft must belong to the reviewed website') unless campaign && review && campaign.site_id == review.comparison.site_id
      errors.add(:base, 'Draft receipt is immutable') if persisted? && changed?
    end
  end
end
