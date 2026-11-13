require 'csv'
class Dashboard::PeopleController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  include LightekIdentity::SensitiveSession
  before_action :sensitive_people!
  protect_from_forgery with: :exception
  layout 'dymond_dash/layouts/dymond_dash'
  before_action :context!
  rescue_from LightekPeople::Access::Denied, with: ->(_) { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: ->(_) { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, LightekPeople::Payroll::Invalid, DymondBank::WorkforcePayouts::Unavailable,
    DymondBank::WorkforcePayouts::ProviderError, ArgumentError, with: :invalid_request

  def index
    return unless @employer
    @departments = LightekPeople::Department.where(employer: @employer).order(:code)
    @people = @access.roster.includes(:worker, :department, manager: :worker).order(:title)
    @plans = LightekPeople::BenefitPlan.where(employer: @employer).order(:name)
    @self_employment = @access.membership
    @enrollments = @self_employment&.benefit_enrollments&.includes(:benefit_plan) || []
    @statements = LightekPeople::PayStatement.joins(:employment).where(lightek_people_employments: {worker_id: current_user.id, employer_id: @employer.id}).includes(:pay_run).where(lightek_people_pay_runs: {status: 'approved'}).references(:pay_run).order(id: :desc).limit(50)
    if @access.payroll?
      @audit_events = LightekPeople::AuditEvent.where(employer: @employer).includes(:actor).order(id: :desc).limit(30)
      @runs = LightekPeople::PayRun.where(employer: @employer).order(id: :desc).limit(30)
      @run = @runs.find_by(id: params[:run_id]) if params[:run_id].present?
      @run ||= @runs.first
      @lines = @run&.pay_statements&.includes(employment: :worker) || []
      @payees = LightekPeople::Employment.where(employer: @employer).includes(:worker).order(:title)
    end
    @sender_configured = DymondBank::WorkforcePayouts.configured?(@employer) if @access.owner? || @access.payroll?
  end

  def department
    mutate!(:people) do
      values = params.require(:department).permit(:name, :code, :parent_id, :active)
      record = params[:record_id].present? ? LightekPeople::Department.where(employer: @employer).find(params[:record_id]) : LightekPeople::Department.new(employer: @employer)
      record.assign_attributes(values)
      if record.persisted? && record.will_save_change_to_active? && record.active? && protected_department?(record.id)
        @access.require!(:owner)
      end
      record.save!
      audit!('department_saved', record)
    end
    back!('Department saved')
  end

  def employment
    mutate!(:people) do
      values = params.require(:employment).permit(:title, :department_id, :manager_id, :level, :worker_kind, :starts_on, :ends_on, :active)
      record = params[:record_id].present? ? LightekPeople::Employment.where(employer: @employer).find(params[:record_id]) : LightekPeople::Employment.new(employer: @employer)
      record.worker = User.find_by!(email_address: params.require(:worker_email).to_s.strip.downcase) if record.new_record?
      if @access.owner?
        values.merge!(params.require(:employment).permit(:people_admin, :payroll_access, :accounting_access, :compliance_access, :directory_admin))
      end
      record.assign_attributes(values)
      unless @access.owner?
        if record.will_save_change_to_department_id? && record.department_id && protected_department?(record.department_id)
          raise LightekPeople::Access::Denied, 'Security-bearing department assignments are managed in IT Directory & access'
        end
        if record.persisted? && restricted_membership?(record) && extends_membership?(record)
          raise LightekPeople::Access::Denied, 'Restoring or extending privileged membership requires the employer owner'
        end
      end
      record.save!
      audit!('employment_saved', record)
    end
    back!('Team member saved')
  end

  def benefit
    mutate!(:prepare) do
      values = params.require(:benefit).permit(:name, :category, :deduction_treatment, :published).to_h.symbolize_keys
      values[:employee_cents] = amount!(params[:benefit][:employee_amount])
      values[:employer_cents] = amount!(params[:benefit][:employer_amount])
      record = params[:record_id].present? ? LightekPeople::BenefitPlan.where(employer: @employer).find(params[:record_id]) : LightekPeople::BenefitPlan.new(employer: @employer)
      record.assign_attributes(values)
      record.save!
      audit!('benefit_plan_saved', record)
    end
    back!('Benefit plan saved', tab: 'benefits')
  end

  def enrollment
    @employer.with_lock do
      @access.require_active!
      employment = LightekPeople::Employment.where(employer: @employer).find(params[:employment_id])
      @access.require!(:prepare) unless employment.worker_id == current_user.id
      raise ArgumentError, 'Choose an active employee membership' unless employment.active_on?(Date.current)
      plan = LightekPeople::BenefitPlan.where(employer: @employer).find(params[:benefit_plan_id])
      record = LightekPeople::BenefitEnrollment.find_by(employment: employment, benefit_plan: plan, ends_on: nil)
      if params[:end] == '1'
        raise ActiveRecord::RecordNotFound unless record
        record.ends_on = Date.current
      else
        raise ArgumentError, 'This benefit plan is not open for enrollment' unless plan.published?
        record ||= LightekPeople::BenefitEnrollment.new(employment: employment, benefit_plan: plan, starts_on: Date.current)
      end
      record.save!
      audit!(params[:end] == '1' ? 'benefit_ended' : 'benefit_elected', record)
    end
    back!('Benefit election saved; plan amounts apply to each prepared pay statement', tab: 'self')
  end

  def pay_run
    mutate!(:prepare) do
      record = LightekPeople::PayRun.create!(params.require(:pay_run).permit(:period_start, :period_end, :pay_date).merge(employer: @employer, prepared_by: current_user))
      audit!('pay_run_created', record)
      @return_run = record.id
    end
    back!('Draft pay run created', tab: 'payroll', run_id: @return_run)
  end

  def statement
    mutate!(:prepare) do
      run = runs.find(params[:id])
      raise ArgumentError, 'Confirm that taxes and deductions were reviewed for this employee and pay period' unless params[:tax_reviewed] == '1'
      source = params.require(:statement)
      values = {tax_reference: source[:tax_reference]}
      %w[gross tax employer_tax other_deductions].each { |field| values["#{field}_cents".to_sym] = amount!(source["#{field}_amount"]) }
      LightekPeople::Payroll.new(access: @access).add!(run: run, employment: LightekPeople::Employment.where(employer: @employer).find(source[:employment_id]), values: values)
    end
    back!('Pay statement calculated and saved', tab: 'payroll', run_id: params[:id])
  end

  def schedule
    mutate!(:release) do
      run = runs.find(params[:id])
      raise ArgumentError, 'Approve the pay run before scheduling payout preparation' unless run.approved?
      run.with_lock do
        at = run.pay_date.in_time_zone('America/New_York').change(hour: 9)
        at = 1.minute.from_now if at < Time.current
        run.update!(preparation_scheduled_at: at,preparation_actor_id: current_user.id,preparation_token: SecureRandom.uuid,preparation_state: 'scheduled',preparation_error_code: nil)
        audit!('payroll_preparation_scheduled',run)
        PayrollPreparationJob.set(wait_until: at).perform_later(run.id,current_user.id,run.preparation_token)
      end
    end
    back!('Payout preparation scheduled. The worker creates reviewable fee quotes; release still needs authorization.',tab: 'payroll',run_id: params[:id])
  end

  def approve
    mutate!(:approve) { LightekPeople::Payroll.new(access: @access).approve!(run: runs.find(params[:id])) }
    back!('Pay run approved; prepare each bank payout to review provider fees', tab: 'payroll', run_id: params[:id])
  end

  def cancel
    mutate!(:approve) { LightekPeople::Payroll.new(access: @access).cancel!(run: runs.find(params[:id])) }
    back!('Pay run canceled', tab: 'payroll', run_id: params[:id])
  end

  def payout
    @access.require!(:release)
    line = LightekPeople::PayStatement.joins(:pay_run).where(lightek_people_pay_runs: {employer_id: @employer.id}).find(params[:id])
    if params[:operation] == 'confirm'
      raise ArgumentError, 'Review the provider fees and confirm release' unless params[:fees_reviewed] == '1'
    end
    LightekPeople::Disbursements.new(access: @access).perform!(statement: line, action: params[:operation], review_digest: params[:review_digest])
    back!('Payout status updated', tab: 'payroll', run_id: line.pay_run_id)
  end

  def export
    @access.require!(:read)
    run = runs.find(params[:id])
    csv = CSV.generate do |out|
      out << %w[statement_id employee period_start period_end pay_date currency gross_cents tax_cents other_deductions_cents benefits_cents net_cents employer_tax_cents employer_benefits_cents tax_reference payout_status provider_reference]
      run.pay_statements.includes(:employment).each do |line|
        cells = [line.id, line.snapshot['name'], run.period_start, run.period_end, run.pay_date, run.currency,
          line.gross_cents, line.tax_cents, line.other_deductions_cents, line.benefit_cents, line.net_cents,
          line.employer_tax_cents, line.employer_benefit_cents, line.tax_reference, line.status, line.provider_ref]
        out << cells.map { |v| v.is_a?(String) && v.match?(/\A[ \t\r\n\f\v\uFEFF]*[=+@\-]|\A[\t\r\n]/) ? "'#{v}" : v }
      end
    end
    audit!('pay_run_exported', run)
    send_data csv, type: 'text/csv', filename: "payroll-#{run.id}-cents.csv", disposition: :attachment
  end

  def sender
    DymondBank::WorkforcePayouts.store!(access: @access, secret_key: params.require(:sender)[:secret_key], financial_account_ref: params[:sender][:financial_account_ref])
    back!('Payout sender verified and securely saved in Vault', tab: 'payroll')
  end

  def bank_setup
    worker = self_employment!
    destination = worker.with_lock { worker.reload.payout_destination || worker.create_payout_destination! }
    url = DymondBank::WorkforcePayouts.new(employer: @employer).onboard!(destination: destination,
      return_url: dashboard_people_bank_return_url(employer_id: @employer.id), refresh_url: dashboard_people_bank_refresh_url(employer_id: @employer.id))
    audit!('bank_setup_opened', destination)
    redirect_to url, allow_other_host: true, status: :see_other
  end

  def bank_return
    worker = self_employment!
    DymondBank::WorkforcePayouts.new(employer: @employer).refresh_destination!(worker.payout_destination) if worker.payout_destination
    back!('Payout eligibility refreshed; leaving the provider form does not guarantee setup is complete', tab: 'self')
  end

  def bank_refresh
    self_employment!
    back!('That secure bank setup link expired. Open bank setup again to continue.', tab: 'self')
  end

  private
  def protected_department?(id)
    defined?(LightekIdentity::ResourceGrant) && LightekIdentity::ResourceGrant.table_exists? && LightekIdentity::ResourceGrant.exists?(employer: @employer,subject_type: 'LightekPeople::Department',subject_id: id)
  end
  def restricted_membership?(record)
    record.people_admin? || record.directory_admin? || record.payroll_access != 'none' || record.accounting_access != 'none' || record.compliance_access != 'none' || protected_department?(record.department_id) ||
      (defined?(LightekIdentity::ResourceGrant) && LightekIdentity::ResourceGrant.table_exists? && LightekIdentity::ResourceGrant.exists?(employer: @employer,subject_type: 'LightekPeople::Employment',subject_id: record.id))
  end
  def extends_membership?(record)
    (record.will_save_change_to_active? && record.active?) ||
      (record.will_save_change_to_starts_on? && record.starts_on && record.starts_on < record.attribute_in_database('starts_on')) ||
      (record.will_save_change_to_ends_on? && record.attribute_in_database('ends_on') && (record.ends_on.nil? || record.ends_on > record.attribute_in_database('ends_on')))
  end
  def sensitive_people!
    financial = %w[department employment benefit enrollment pay_run statement schedule approve cancel payout export sender bank_setup bank_return bank_refresh]
    financial_page = action_name == 'index' && %w[payroll self benefits].include?(params[:tab])
    grants = action_name == 'employment' && params[:employment]&.keys&.any? { |key| %w[people_admin payroll_access accounting_access compliance_access directory_admin].include?(key) }
    require_sensitive_session! if financial.include?(action_name) || financial_page || grants
  end
  def context!
    return head :unauthorized unless current_user
    @employers = LightekPeople::Access.employers_for(current_user)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.first
    if @employer
      @access = LightekPeople::Access.new(actor: current_user, employer: @employer)
      LightekPeople::StarterDepartments.ensure!(@employer) if @access.people_admin?
    elsif action_name != 'index'
      head :forbidden
    end
    response.set_header('Cache-Control', 'no-store')
  end
  def runs = LightekPeople::PayRun.where(employer: @employer)
  def self_employment!
    worker = @access.membership
    raise LightekPeople::Access::Denied, 'Only the worker can change their payout destination' unless worker && worker.worker_id == current_user.id
    worker
  end
  def mutate!(permission)
    @employer.with_lock do
      @access.require!(permission)
      yield
    end
  end
  def audit!(action, record)
    LightekPeople::AuditEvent.record!(employer: @employer, actor: current_user, action: action, record: record)
  end
  def amount!(value)
    source = value.to_s
    raise ArgumentError, 'Enter a dollar amount with at most two decimal places' unless source.match?(/\A\d{1,7}(?:\.\d{1,2})?\z/)
    (BigDecimal(source) * 100).to_i
  end
  def back!(notice, tab: params[:tab].presence || 'directory', run_id: nil)
    redirect_to dashboard_people_path(employer_id: @employer&.id, tab: tab, run_id: run_id), notice: notice, status: :see_other
  end
  def invalid_request(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
    fallback = case action_name
    when 'bank_setup','bank_return','bank_refresh','enrollment' then 'self'
    when 'benefit' then 'benefits'
    when 'pay_run','statement','approve','cancel','schedule','payout','sender' then 'payroll'
    else 'directory'
    end
    run_id = params[:run_id].presence || (params[:id] if %w[statement approve cancel schedule].include?(action_name))
    redirect_to dashboard_people_path(employer_id: @employer&.id, tab: params[:tab].presence || fallback, run_id: run_id), alert: message, status: :see_other
  end
end
