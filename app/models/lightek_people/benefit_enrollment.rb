module LightekPeople
  class BenefitEnrollment < ApplicationRecord
    self.table_name = 'lightek_people_benefit_enrollments'
    belongs_to :employment
    belongs_to :benefit_plan
    validates :benefit_plan_id, uniqueness: {scope: :employment_id, conditions: -> { where(ends_on: nil) }}, if: -> { ends_on.nil? }
    validates :starts_on, presence: true
    validate do
      errors.add(:benefit_plan, 'must belong to the employer') unless benefit_plan.employer_id == employment.employer_id
      errors.add(:employment, 'benefits currently support employee enrollment') unless employment.worker_kind == 'employee'
      errors.add(:ends_on, 'must follow the start date') if ends_on && starts_on && ends_on < starts_on
    end
    def covers?(date) = starts_on <= date && (ends_on.nil? || ends_on > date)
  end
end
