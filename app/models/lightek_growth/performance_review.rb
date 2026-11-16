module LightekGrowth
  class PerformanceReview < ApplicationRecord
    self.table_name = 'lightek_growth_performance_reviews'
    belongs_to :comparison, class_name: 'LightekGrowth::Comparison'
    belongs_to :created_by, class_name: 'User'
    has_one :followup, class_name: 'LightekGrowth::PerformanceDraft', foreign_key: :review_id
    validates :request_key, format: {with: /\A[a-zA-Z0-9_-]{8,100}\z/}, uniqueness: {scope: :comparison_id}
    validate { errors.add(:base, 'Measured reviews are immutable; request a fresh review') if persisted? && changed? }
  end
end
