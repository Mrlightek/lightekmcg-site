module LightekGrowth
  class Visit < ApplicationRecord
    self.table_name = 'lightek_growth_visits'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :link, class_name: 'LightekGrowth::Link'
    before_validation(on: :create) { self.token ||= SecureRandom.hex(24) }
    after_create_commit { Rails.logger.info({event: 'lightek.growth.visit_recorded', site_id: site_id, link_id: link_id, visit_id: id}.to_json) }
    validates :token, presence: true, uniqueness: true
    validate do
      errors.add(:link, 'must belong to this website') if link && link.site_id != site_id
      errors.add(:base, 'Recorded visits are immutable') if persisted? && changed?
    end
    def description = "#{link.campaign.name} · #{link.source} / #{link.medium} · #{link.label}"
  end
end
