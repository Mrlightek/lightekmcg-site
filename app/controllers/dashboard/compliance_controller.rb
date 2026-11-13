class Dashboard::ComplianceController < ApplicationController
  include LightekIdentity::SensitiveSession
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :context!
  rescue_from LightekPeople::Access::Denied, with: ->(_) { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: ->(_) { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: ->(error) { redirect_to dashboard_compliance_path(employer_id: @employer&.id),alert: error.message }
  def index
    people = LightekPeople::Access.new(actor: current_user,employer: @employer)
    @is_owner = people.owner?
    @can_manage = @is_owner || people.membership&.compliance_access == 'administrator'
    @monitors = LightekCompliance::Monitor.where(employer: @employer).order(:state,:id)
  end
  def create
    LightekCompliance::Access.authorize!(current_user,@employer,write: true)
    values = params.require(:monitor).permit(:state,:provider,:query)
    monitor = LightekCompliance::Monitor.create!(values.merge(employer: @employer,actor: current_user,next_run_at: Time.current))
    JurisdictionMonitorJob.perform_later(monitor.id)
    redirect_to dashboard_compliance_path(employer_id: @employer.id),notice: 'Jurisdiction monitor created; results remain marked for legal review.'
  end
  def credentials
    return head(:forbidden) if Current.session.connect_delegation.present?
    people = LightekPeople::Access.new(actor: current_user,employer: @employer)
    people.require!(:owner)
    raise LightekPeople::Access::Denied unless current_user.authenticate(params[:password].to_s)
    provider = params[:provider]
    raise ArgumentError,'Choose a supported source' unless %w[openstates ny_openleg].include?(provider)
    key = params[:api_key].to_s.strip
    raise ArgumentError,'Enter a valid API key' unless key.length.between?(8,2000) && !key.match?(/\s/)
    LightekVault::Service.store!(name: "Jurisdiction monitoring · #{@employer.id} · #{provider}",slug: LightekCompliance::Sources.slug(@employer,provider),
      payload: {'api_key'=>key},provider: provider,purpose: 'jurisdiction_monitoring',
      access_policy: {'consumers'=>[LightekCompliance::Sources.name],'purposes'=>['jurisdiction_monitoring']},requested_by: current_user.email_address)
    redirect_to dashboard_compliance_path(employer_id: @employer.id),notice: 'Source credential saved in Vault. Refresh a monitor to test access.'
  end
  def refresh
    LightekCompliance::Access.authorize!(current_user,@employer,write: true)
    monitor = LightekCompliance::Monitor.where(employer: @employer).find(params[:id])
    monitor.with_lock do
      raise ArgumentError,'Wait one minute between manual source refreshes' if monitor.last_checked_at && monitor.last_checked_at > 1.minute.ago
      monitor.update!(next_run_at: Time.current)
    end
    JurisdictionMonitorJob.perform_later(monitor.id)
    redirect_to dashboard_compliance_path(employer_id: @employer.id),notice: 'Source refresh queued'
  end
  def destroy
    LightekCompliance::Access.authorize!(current_user,@employer,write: true)
    LightekCompliance::Monitor.where(employer: @employer).find(params[:id]).update!(enabled: false)
    redirect_to dashboard_compliance_path(employer_id: @employer.id),notice: 'Monitor stopped'
  end
  private
  def context!
    response.headers['Cache-Control']='no-store'
    require_sensitive_session!
    return if performed?
    @employers = LightekPeople::Access.employers_for(current_user)
    @employer = params[:employer_id].present? ? @employers.find(params[:employer_id]) : @employers.first!
    LightekCompliance::Access.authorize!(current_user,@employer)
  end
end
