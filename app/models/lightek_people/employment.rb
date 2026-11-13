module LightekPeople
  class Employment < ApplicationRecord
    self.table_name = 'lightek_people_employments'
    LEVELS = %w[individual_contributor team_lead manager].freeze
    KINDS = %w[employee freelancer agency].freeze
    belongs_to :employer, class_name: 'User'
    belongs_to :worker, class_name: 'User'
    belongs_to :department, optional: true
    belongs_to :manager, class_name: name, optional: true
    has_many :direct_reports, class_name: name, foreign_key: :manager_id, dependent: :restrict_with_exception
    has_many :benefit_enrollments, dependent: :restrict_with_exception
    has_one :payout_destination, dependent: :restrict_with_exception
    validates :worker_id, uniqueness: {scope: :employer_id}
    validates :title, presence: true, length: {maximum: 160}
    validates :starts_on, presence: true
    validates :level, inclusion: {in: LEVELS}
    validates :worker_kind, inclusion: {in: KINDS}
    validates :payroll_access, inclusion: {in: %w[none preparer approver administrator]}
    validate :organization_and_reporting
    scope :active, -> { where(active: true).where('starts_on <= ?', Date.current).where('ends_on IS NULL OR ends_on >= ?', Date.current) }
    def active_on?(date) = active? && starts_on <= date && (ends_on.nil? || ends_on >= date)
    def worked_during?(first, last)
      starts_on <= last && (ends_on.nil? || ends_on >= first) && (active? || ends_on.present?)
    end
    private
    def organization_and_reporting
      errors.add(:department, 'belongs to another employer') if department && department.employer_id != employer_id
      errors.add(:ends_on, 'must follow the start date') if ends_on && starts_on && ends_on < starts_on
      seen = [id].compact
      node = manager
      while node
        if node.employer_id != employer_id || seen.include?(node.id) || node.level == 'individual_contributor'
          errors.add(:manager, 'must be a manager or team lead in this employer, without a reporting cycle')
          break
        end
        seen << node.id
        node = node.manager
      end
      if manager && manager.level == 'team_lead' && level != 'individual_contributor'
        errors.add(:manager, 'a team lead can supervise individual contributors only')
      end
      if persisted? && level == 'team_lead' && direct_reports.where.not(level: 'individual_contributor').exists?
        errors.add(:level, 'reassign leadership reports before changing to team lead')
      end
      if persisted? && level == 'individual_contributor' && direct_reports.exists?
        errors.add(:level, 'reassign direct reports before removing the leadership role')
      end
    end
  end
end
