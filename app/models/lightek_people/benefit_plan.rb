module LightekPeople
  class BenefitPlan < ApplicationRecord
    self.table_name = 'lightek_people_benefit_plans'
    belongs_to :employer, class_name: 'User'
    has_many :benefit_enrollments, dependent: :restrict_with_exception
    validates :name, presence: true, length: {maximum: 160}
    validates :category, inclusion: {in: %w[health dental vision retirement life disability other]}
    validates :deduction_treatment, inclusion: {in: %w[pre_tax post_tax]}
    validates :currency, inclusion: {in: %w[USD]}
    validates :employee_cents, :employer_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000_000}
  end
end
