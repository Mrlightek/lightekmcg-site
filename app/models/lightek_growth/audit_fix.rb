module LightekGrowth
  class AuditFix < ApplicationRecord
    self.table_name = 'lightek_growth_audit_fixes'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :finding, class_name: 'LightekGrowth::AuditFinding'
    belongs_to :created_by, class_name: 'User'
    belongs_to :applied_by, class_name: 'User', optional: true
    belongs_to :rolled_back_by, class_name: 'User', optional: true
    validates :status, inclusion: {in: %w[prepared applied rolled_back]}
    validate do
      errors.add(:finding, 'must belong to this website') if finding && finding.site_id != site_id
      errors.add(:base, 'Reviewed change is immutable; prepare another preview') if persisted? && (changes.keys & %w[site_id finding_id created_by_id baseline before_values after_values]).any?
    end
  end
end
