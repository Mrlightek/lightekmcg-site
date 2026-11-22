class Dashboard::LifecycleController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  include LightekIdentity::SensitiveSession
  before_action :require_sensitive_session!
  before_action :context!
  protect_from_forgery with: :exception
  rescue_from LightekPeople::Access::Denied do
    head :forbidden
  end
  rescue_from ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, ArgumentError do |error|
    redirect_to dashboard_lifecycle_path(employer_id: @employer.id), alert: error.message
  end
  def index
    @cases = LightekPeople::LifecycleCase.where(employer: @employer).includes(:subject, :created_by).order(created_at: :desc).limit(100)
    @cases = @cases.where(id: params[:case_id]) if params[:case_id].present?
    @people = LightekPeople::Employment.where(employer: @employer).includes(:worker).order(:title)
    @agencies = User.where(agency_id: @employer.id, role: 'white_label').order(:email_address)
  end
  def start
    kind = params.require(:kind).to_s
    subject = if kind.start_with?('employee_')
      LightekPeople::Employment.where(employer: @employer).find(params.require(:subject_id))
    else
      User.where(agency_id: @employer.id, role: 'white_label').find(params.require(:subject_id))
    end
    @workflow.start!(kind: kind, subject: subject)
    redirect_to dashboard_lifecycle_path(employer_id: @employer.id), notice: 'Lifecycle prepared. Offboarding access revocation is a separate explicit action.', status: :see_other
  end
  def step
    @workflow.attest!(id: params[:id], step: params.require(:step), evidence: params.require(:evidence), version: params.require(:lock_version))
    back!('Checklist evidence saved.')
  end
  def revoke
    raise ArgumentError, 'Review and confirm the access revocation and work handoff.' unless params[:confirmed] == '1'
    @workflow.revoke!(id: params[:id], version: params.require(:lock_version))
    back!('Application access revoked and open sales work handed off. Confirm external access and directory completion in the checklist.')
  end
  def cancel
    @workflow.cancel!(id: params[:id], version: params.require(:lock_version))
    back!('Onboarding canceled without activating access.')
  end
  def complete
    @workflow.complete!(id: params[:id], version: params.require(:lock_version))
    back!('Lifecycle completed.')
  end
  private
  def back!(message) = redirect_to(dashboard_lifecycle_path(employer_id: @employer.id), notice: message, status: :see_other)
  def context!
    @employers = LightekPeople::Lifecycle.employers_for(current_user)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : (@employers.find_by(id: current_user.id) || @employers.first!)
    LightekPeople::Lifecycle.authorize_review!(actor: current_user, employer: @employer)
    @workflow = LightekPeople::Lifecycle.new(actor: current_user, employer: @employer)
  end
end
