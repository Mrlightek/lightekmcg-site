module LightekGrowth
  class FeatureShowcase < ApplicationRecord
    self.table_name = 'lightek_growth_feature_showcases'
    belongs_to :marketing_kit, class_name: 'LightekGrowth::MarketingKit'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :page, class_name: 'DymondSite::Page'
    belongs_to :created_by, class_name: 'User'
    belongs_to :approved_by, class_name: 'User', optional: true
    has_many :clips, -> { order(:position) }, class_name: 'LightekGrowth::FeatureClip', dependent: :restrict_with_error
    validates :status, inclusion: {in: %w[pending running completed failed]}
    validates :token, presence: true, uniqueness: true
    validate do
      errors.add(:base, 'Keep the kit and page in this website') unless marketing_kit&.site_id == site_id && page&.site_id == site_id
      errors.add(:snapshot, 'must remain immutable') if persisted? && (changes.keys & %w[marketing_kit_id site_id page_id created_by_id token snapshot]).any?
    end
  end
end
