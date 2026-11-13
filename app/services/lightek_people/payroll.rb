module LightekPeople
  class Payroll
    class Invalid < StandardError; end
    def initialize(access:)
      @access = access
    end
    def add!(run:, employment:, values:)
      @access.require!(:prepare)
      run.with_lock do
        local!(run)
        raise Invalid, 'Only draft runs can be edited' unless run.draft?
        raise Invalid, 'Choose a worker employed during this pay period' unless employment.employer_id == run.employer_id && employment.worked_during?(run.period_start, run.period_end)
        line = run.pay_statements.find_or_initialize_by(employment: employment)
        line.prepared_by = @access.actor
        line.assign_attributes(values.slice(:gross_cents, :tax_cents, :employer_tax_cents, :other_deductions_cents, :tax_reference))
        elections = employment.benefit_enrollments.includes(:benefit_plan).select { |e| e.covers?(run.pay_date) }
        benefits = elections.map do |e|
          plan = e.benefit_plan
          raise Invalid, 'Benefit currency differs from this pay run' unless plan.currency == run.currency
          {'name'=>plan.name, 'plan_id'=>plan.id, 'treatment'=>plan.deduction_treatment, 'employee_cents'=>plan.employee_cents, 'employer_cents'=>plan.employer_cents}
        end
        line.benefit_cents = benefits.sum { |b| b['employee_cents'] }
        line.employer_benefit_cents = benefits.sum { |b| b['employer_cents'] }
        line.net_cents = line.gross_cents.to_i - line.tax_cents.to_i - line.other_deductions_cents.to_i - line.benefit_cents
        line.snapshot = {'name'=>employment.worker.full_name, 'title'=>employment.title, 'worker_kind'=>employment.worker_kind,
          'department'=>employment.department&.name, 'benefits'=>benefits, 'tax_method'=>'externally_reviewed',
          'period_start'=>run.period_start.iso8601, 'period_end'=>run.period_end.iso8601}
        line.save!
        audit!('pay_statement_prepared', line)
        line
      end
    end
    def approve!(run:)
      @access.require!(:approve)
      run.with_lock do
        local!(run)
        return run if run.approved?
        raise Invalid, 'Only a draft can be approved' unless run.draft?
        raise Invalid, 'Add at least one pay statement' unless run.pay_statements.exists?
        participated = AuditEvent.where(employer_id: run.employer_id, actor_id: @access.actor.id, action: 'pay_statement_prepared', record_type: 'LightekPeople::PayStatement', record_id: run.pay_statements.select(:id)).exists?
        raise Invalid, 'A different payroll approver must approve this run' if run.prepared_by_id == @access.actor.id || run.pay_statements.exists?(prepared_by_id: @access.actor.id) || participated
        account = DymondBank::WorkforcePayouts.new(employer: @access.employer).financial_account_ref
        run.pay_statements.each do |line|
          raise Invalid, 'A worker’s dates do not cover this pay period' unless line.employment.worked_during?(run.period_start, run.period_end)
          line.validate!
          line.update!(status: 'approved')
        end
        run.update!(status: 'approved', approved_by: @access.actor, approved_at: Time.current, financial_account_ref: account)
        audit!('pay_run_approved', run)
      end
      run
    end
    def cancel!(run:)
      @access.require!(:approve)
      run.with_lock do
        local!(run)
        raise Invalid, 'A run with provider attempts cannot be canceled' if run.pay_statements.where.not(attempted_at: nil).exists?
        run.update!(status: 'canceled')
        audit!('pay_run_canceled', run)
      end
    end
    private
    def local!(run)
      raise Access::Denied, 'Pay run belongs to another employer' unless run.employer_id == @access.employer.id
    end
    def audit!(action, record)
      AuditEvent.record!(employer: @access.employer, actor: @access.actor, action: action, record: record)
    end
  end
end
