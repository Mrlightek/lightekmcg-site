module LightekPeople
  class LifecycleCase < ApplicationRecord
    self.table_name = 'lightek_people_lifecycle_cases'
    belongs_to :employer, class_name: 'User'
    belongs_to :subject, polymorphic: true
    belongs_to :created_by, class_name: 'User'
    belongs_to :revoked_by, class_name: 'User', optional: true
    belongs_to :completed_by, class_name: 'User', optional: true
    validates :kind, inclusion: {in: %w[employee_onboarding employee_offboarding agency_onboarding agency_offboarding]}
    validates :status, inclusion: {in: %w[open access_revoked completed canceled]}
    validate do
      allowed = kind.to_s.start_with?('employee_') ? subject.is_a?(Employment) && subject.employer_id == employer_id : subject.is_a?(User) && subject.role == 'white_label' && subject.agency_id == employer_id
      errors.add(:subject, 'must belong directly to this employer or upstream agency') unless allowed
    end
  end
end
