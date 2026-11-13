module LightekPeople
  class PayRun < ApplicationRecord
    self.table_name = 'lightek_people_pay_runs'
    belongs_to :employer, class_name: 'User'
    belongs_to :prepared_by, class_name: 'User'
    belongs_to :approved_by, class_name: 'User', optional: true
    has_many :pay_statements, dependent: :restrict_with_exception
    validates :period_start, :period_end, :pay_date, presence: true
    validates :currency, inclusion: {in: %w[USD]}
    validates :status, inclusion: {in: %w[draft approved canceled]}
    validates :period_start, uniqueness: {scope: [:employer_id, :period_end, :pay_date], conditions: -> { where.not(status: 'canceled') }}, unless: -> { status == 'canceled' }
    validate :approved_identity_is_immutable, on: :update
    def approved_identity_is_immutable
      if approved_at_was && %w[employer_id period_start period_end pay_date currency prepared_by_id financial_account_ref approved_by_id approved_at].any? { |field| will_save_change_to_attribute?(field) }
        errors.add(:base, 'Approved payroll identity and period cannot be changed')
      end
    end
    validate do
      errors.add(:period_end, 'must follow period start') if period_start && period_end && period_end < period_start
      errors.add(:pay_date, 'must not precede the pay period') if pay_date && period_end && pay_date < period_end
    end
    def approved? = status == 'approved'
    def draft? = status == 'draft'
  end
end
