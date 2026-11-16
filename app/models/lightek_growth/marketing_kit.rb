module LightekGrowth
  class MarketingKit < ApplicationRecord
    self.table_name = 'lightek_growth_marketing_kits'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    has_many :check_ins, class_name: 'LightekGrowth::MarketingCheckIn', dependent: :restrict_with_error
    validates :request_key, presence: true, uniqueness: {scope: :site_id}
    validates :starts_on, presence: true
    validate do
      errors.add(:campaign, 'must belong to this website') if campaign && campaign.site_id != site_id
      errors.add(:snapshot, 'must be a bounded object') unless snapshot.is_a?(Hash) && snapshot.to_json.bytesize <= 100_000
      errors.add(:base, 'Marketing kit history is immutable; prepare another kit') if persisted? && changed?
    end
    before_destroy { throw :abort }
  end
end
