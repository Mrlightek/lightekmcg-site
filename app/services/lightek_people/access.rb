module LightekPeople
  class Access
    class Denied < StandardError; end
    BUSINESS_ROLES = %w[client white_label admin super_admin].freeze
    def self.employers_for(actor)
      ids = Employment.where(worker_id: actor.id).pluck(:employer_id)
      ids << actor.id if BUSINESS_ROLES.include?(actor.role)
      User.where(id: ids.uniq)
    end
    attr_reader :actor, :employer, :membership
    def initialize(actor:, employer:)
      @actor, @employer = actor, employer
      @membership = Employment.find_by(employer_id: employer.id, worker_id: actor.id)
      raise Denied, 'This employer has not granted access' unless owner? || membership
    end
    def owner? = actor.id == employer.id && BUSINESS_ROLES.include?(actor.role)
    def people_admin? = owner? || (membership&.active_on?(Date.current) && membership.people_admin?)
    def directory_admin? = owner? || (membership&.active_on?(Date.current) && membership.directory_admin?)
    def payroll?(action = :read)
      return true if owner?
      return false unless membership&.active_on?(Date.current)
      roles = case action.to_sym
      when :prepare then %w[preparer administrator]
      when :approve, :release then %w[approver administrator]
      else %w[preparer approver administrator]
      end
      roles.include?(membership&.payroll_access)
    end
    def require_active!
      @membership&.reload
      raise Denied, 'This employer membership is no longer active' unless owner? || @membership&.active_on?(Date.current)
    rescue ActiveRecord::RecordNotFound
      raise Denied, 'This employer membership no longer exists'
    end
    def require!(permission)
      require_active!
      allowed = case permission
      when :people then people_admin?
      when :owner then owner?
      when :directory then directory_admin?
      else payroll?(permission)
      end
      raise Denied, 'Your employer has not granted this permission' unless allowed
    end
    def roster
      scope = Employment.where(employer_id: employer.id)
      return scope if people_admin?
      ids = [membership.id]
      frontier = ids
      if membership.active_on?(Date.current) && membership.level.in?(%w[manager team_lead])
        while frontier.any?
          frontier = scope.where(manager_id: frontier).where.not(id: ids).pluck(:id)
          ids.concat(frontier)
        end
      end
      scope.where(id: ids)
    end
  end
end
