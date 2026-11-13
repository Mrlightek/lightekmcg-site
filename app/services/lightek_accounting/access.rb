module LightekAccounting
  class Access
    class Denied < StandardError; end
    attr_reader :actor, :employer
    def initialize(actor:,employer:)
      @actor, @employer = actor, employer
      @people = LightekPeople::Access.new(actor: actor,employer: employer)
    end
    def require!(permission = :read)
      @people.require_active!
      member = @people.membership
      allowed = @people.owner? || case permission
      when :write then %w[bookkeeper administrator].include?(member&.accounting_access)
      when :review then %w[reviewer administrator].include?(member&.accounting_access)
      when :admin then member&.accounting_access == 'administrator'
      else %w[bookkeeper reviewer administrator].include?(member&.accounting_access)
      end
      raise Denied, 'Accounting access must be explicitly assigned by this employer' unless allowed
      self
    rescue LightekPeople::Access::Denied
      raise Denied, 'Employer membership is inactive or unavailable'
    end
    def allowed?(permission)
      require!(permission)
      true
    rescue Denied
      false
    end
    def books = Book.where(employer: employer)
    def book!(id,permission = :read)
      require!(permission)
      books.find(id)
    end
  end
end
