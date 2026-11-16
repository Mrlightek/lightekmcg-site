class Dashboard::AgenciesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_agency_access!
  rate_limit to: 5, within: 3.minutes, only: :send_setup_invitation
  def index
    response.headers['Cache-Control'] = 'private, no-store'
    @agencies = agency_scope.includes(:agency_profile, :agency).order(:email_address)
    @agency = if params[:agency_id].present?
      @agencies.find(params[:agency_id])
    else
      @agencies.find_by(id: current_user.id) || @agencies.first
    end
    return unless @agency

    clients = @agency.agency_clients.where(role: 'client').order(:email_address)
    @selected_client = clients.find(params[:client_id]) if params[:client_id].present?
    query = params[:q].to_s.strip.first(100)
    clients = clients.where('LOWER(email_address) LIKE ?', "%#{User.sanitize_sql_like(query.downcase)}%") if query.present?
    @clients = clients.limit(100)
    if @selected_client
      @client_sites = LightekAgency::Access.sites_for(current_user)
        .where(id: LightekSettings::WebsiteIdentity.sites_for(@selected_client).select(:id)).order(:name)
      @client_installations = LightekCommerce::Installations.scope_for(current_user, operator: current_user.role == 'super_admin')
        .where(hosting_owner_id: @selected_client.id).order(created_at: :desc).limit(10)
        .map { |order| [order, LightekCommerce::Installations.summary(order)] }
    end
  end
  def create
    User.transaction do
      scope = current_user.role == "super_admin" ? User.where(role: "client") : current_user.agency_clients.where(role: "client")
      user = scope.find(params.require(:user_id))
      user.update!(role: "white_label", agency: user.agency || current_user)
      user.create_agency_profile!(brand_name: params.require(:brand_name))
      if defined?(LightekPeople::Lifecycle) && LightekPeople::LifecycleCase.table_exists?
        LightekPeople::Lifecycle.new(actor: current_user, employer: user.agency).start!(kind: 'agency_onboarding', subject: user)
      end
    end
    redirect_to dashboard_agencies_path, notice: "White label agency enabled."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path, alert: error.record.errors.full_messages.to_sentence
  end
  def update
    user = agency_scope.find(params[:id])
    profile = user.agency_profile || user.build_agency_profile
    profile.update!(params.require(:agency_profile).permit(:brand_name, :logo_url, :support_email, :accent_color))
    redirect_to dashboard_agencies_path(agency_id: user.id), notice: "Agency branding saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path(agency_id: user&.id), alert: error.record.errors.full_messages.to_sentence
  end
  def update_terms
    user = agency_scope.find(params[:id])
    raise CanCan::AccessDenied unless current_user.role == "super_admin" || user.agency_id == current_user.id
    user.with_lock do
      user.update!(upstream_share_bps: params.require(:upstream_share_bps))
      User.where(id: user.managed_account_ids).find_each do |account|
        terms = LightekCommerce::RevenueSharing.snapshot_for(account)
        raise ArgumentError, "Combined upstream shares exceed 100%" if terms.sum { |row| row.fetch("basis_points") } > 10_000
      end
    end
    redirect_to dashboard_agencies_path(agency_id: user.id), notice: "Revenue terms saved for future purchases. Existing orders and subscriptions keep their agreed terms."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to dashboard_agencies_path(agency_id: user&.id), alert: error.message
  end
  def create_client
    agency = agency_scope.find(params[:id])
    values = params.require(:client).permit(:first_name, :last_name, :email_address)
    client = agency.agency_clients.create!(values.merge(role: "client", password_setup_required: true, password: SecureRandom.urlsafe_base64(36)))
    if client.password_setup_invitation_error
      redirect_to dashboard_agencies_path(agency_id: agency.id, client_id: client.id, anchor: 'client-setup'), alert: 'Client account created, but invitation could not be queued. Use Send setup invitation to retry.'
    else
      redirect_to dashboard_agencies_path(agency_id: agency.id, client_id: client.id, anchor: 'client-setup'), notice: 'Client account created. A first-password invitation is queued for the client.'
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path(agency_id: agency&.id), alert: error.record.errors.full_messages.to_sentence
  end
  def send_setup_invitation
    agency = agency_scope.find(params[:id])
    client = agency.agency_clients.find(params.require(:client_id))
    begin
      client.send_password_setup_invitation!
    rescue ArgumentError
      raise
    rescue StandardError => error
      Rails.logger.warn("[Account setup] resend failed user=#{client.id} #{error.class}")
      return redirect_to dashboard_agencies_path(agency_id: agency.id, client_id: client.id, anchor: 'client-setup'), alert: 'Invitation could not be queued. The account is preserved; retry when mail workers are available.'
    end
    redirect_to dashboard_agencies_path(agency_id: agency.id, client_id: client.id, anchor: 'client-setup'), notice: 'Password setup invitation queued for the client.'
  rescue ArgumentError
    redirect_to dashboard_agencies_path(agency_id: agency.id, client_id: client.id, anchor: 'client-setup'), alert: 'This account already has a chosen password. Its owner can use Forgot password.'
  end
  private
  def require_agency_access!
    return head(:forbidden) unless current_user&.role.in?(%w[super_admin white_label]) && (!defined?(LightekPeople::LifecycleAccess) || LightekPeople::LifecycleAccess.active?(current_user))
    head :forbidden if defined?(LightekPeople::LifecycleAccess) && !LightekPeople::LifecycleAccess.agency_ready?(current_user) && !action_name.in?(%w[index update])
  end
  def agency_scope
    current_user.role == "super_admin" ? User.where(role: "white_label") : User.where(id: current_user.managed_account_ids, role: "white_label")
  end
end
