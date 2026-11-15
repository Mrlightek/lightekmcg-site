module LightekGrowth
  class AuditFinding < ApplicationRecord
    self.table_name = 'lightek_growth_audit_findings'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :website_audit, class_name: 'LightekGrowth::WebsiteAudit'
    belongs_to :resolved_by, class_name: 'User', optional: true
    validates :status, inclusion: {in: %w[open resolved dismissed]}
    validates :severity, inclusion: {in: %w[high medium low]}
    validate do
      errors.add(:website_audit, 'must belong to this website') if website_audit && website_audit.site_id != site_id
      errors.add(:base, 'Finding evidence is immutable') if persisted? && (changes.keys & %w[site_id website_audit_id page_id rule locator severity title evidence fix_target]).any?
    end
  end
end
