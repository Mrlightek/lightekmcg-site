module LightekGrowth
  class Plan < ApplicationRecord
    self.table_name = 'lightek_growth_plans'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    belongs_to :previous_plan, class_name: 'LightekGrowth::Plan', optional: true
    has_many :steps, -> { order(:position) }, class_name: 'LightekGrowth::Step', dependent: :restrict_with_error
    validates :plan_on, :request_key, :playbook_version, presence: true
    validates :revision, numericality: {only_integer: true, greater_than: 0}
    validate do
      errors.add(:snapshot, 'must be a bounded object') unless snapshot.is_a?(Hash) && snapshot.to_json.bytesize <= 64_000
      errors.add(:base, 'Prepared plan evidence is immutable; prepare another revision') if persisted? && changed?
      errors.add(:previous_plan, 'must be an earlier revision for this website and day') if previous_plan && (previous_plan.site_id != site_id || previous_plan.plan_on != plan_on || previous_plan.revision >= revision)
    end
    def current?
      plan_on == Date.current && self.class.where(site_id: site_id, plan_on: plan_on).maximum(:revision) == revision
    end
  end
end
