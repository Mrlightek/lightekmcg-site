module LightekGrowth
  class ComparisonArm < ApplicationRecord
    self.table_name = 'lightek_growth_comparison_arms'
    belongs_to :comparison, class_name: 'LightekGrowth::Comparison'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :link, class_name: 'LightekGrowth::Link'
    validates :label, inclusion: {in: %w[control challenger]}, uniqueness: {scope: :comparison_id}
    validates :content_digest, format: {with: /\A[0-9a-f]{64}\z/}
    validate do
      errors.add(:base, 'Campaign and tracked link must match the comparison website') unless comparison && campaign && link && campaign.site_id == comparison.site_id && link.site_id == comparison.site_id && link.campaign_id == campaign_id
      errors.add(:base, 'Creative and placement evidence is immutable') if persisted? && changed?
    end
  end
end
