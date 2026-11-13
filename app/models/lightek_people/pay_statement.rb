module LightekPeople
  class PayStatement < ApplicationRecord
    self.table_name = 'lightek_people_pay_statements'
    belongs_to :pay_run
    belongs_to :employment
    belongs_to :prepared_by, class_name: 'User'
    validates :employment_id, uniqueness: {scope: :pay_run_id}
    validates :gross_cents, :tax_cents, :employer_tax_cents, :other_deductions_cents, :benefit_cents, :employer_benefit_cents, :net_cents,
      numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000_000}
    validates :tax_reference, presence: true, length: {maximum: 300}
    validates :status, inclusion: {in: %w[draft approved preparing review pending posted failed returned requires_action]}
    validate :approved_amounts_are_immutable, on: :update
    def approved_amounts_are_immutable
      if PayRun.where(id: pay_run_id).where.not(approved_at: nil).exists? &&
          %w[pay_run_id employment_id prepared_by_id gross_cents tax_cents employer_tax_cents other_deductions_cents benefit_cents employer_benefit_cents net_cents snapshot tax_reference].any? { |field| will_save_change_to_attribute?(field) }
        errors.add(:base, 'Approved pay statement amounts and identity cannot be changed')
      end
    end
    validate do
      errors.add(:employment, 'belongs to another employer') unless employment.employer_id == pay_run.employer_id
      errors.add(:net_cents, 'does not match gross less deductions') unless net_cents == gross_cents.to_i - tax_cents.to_i - other_deductions_cents.to_i - benefit_cents.to_i
    end
  end
end
