module LightekGrowth
  class Comparison < ApplicationRecord
    self.table_name = 'lightek_growth_comparisons'
    VARIABLES = %w[message creative call_to_action landing].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    has_many :arms, class_name: 'LightekGrowth::ComparisonArm'
    has_many :reviews, class_name: 'LightekGrowth::PerformanceReview'
    validates :request_key, format: {with: /\A[a-zA-Z0-9_-]{8,100}\z/}
    validates :name, presence: true, length: {maximum: 160}
    validates :hypothesis, presence: true, length: {maximum: 1000}
    validates :variable, inclusion: {in: VARIABLES}
    validate do
      errors.add(:ends_on, 'must form a window of 1–90 days') unless starts_on && ends_on && (ends_on - starts_on).in?(0..89)
      errors.add(:base, 'Comparison inputs are immutable; prepare another comparison') if persisted? && changed?
    end
  end
end
