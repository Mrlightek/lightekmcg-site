module LightekGrowth
  class WebsiteAudit < ApplicationRecord
    self.table_name = 'lightek_growth_website_audits'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    has_many :findings, class_name: 'LightekGrowth::AuditFinding'
    validate { errors.add(:base, 'Audit snapshots are immutable; run another audit') if persisted? && changed? }
    validates :status, inclusion: {in: %w[completed partial]}
    validates :request_key, :rules_version, presence: true
  end
end
