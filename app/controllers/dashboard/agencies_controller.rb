class Dashboard::AgenciesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_agency_access!
  def index
    @agencies = agency_scope.includes(:agency_profile, :agency).order(:email_address)
  end
  def create
    User.transaction do
      scope = current_user.role == "super_admin" ? User.where(role: "client") : current_user.agency_clients.where(role: "client")
      user = scope.find(params.require(:user_id))
      user.update!(role: "white_label", agency: user.agency || current_user)
      user.create_agency_profile!(brand_name: params.require(:brand_name))
    end
    redirect_to dashboard_agencies_path, notice: "White label agency enabled."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path, alert: error.record.errors.full_messages.to_sentence
  end
  def update
    user = agency_scope.find(params[:id])
    profile = user.agency_profile || user.build_agency_profile
    profile.update!(params.require(:agency_profile).permit(:brand_name, :logo_url, :support_email, :accent_color))
    redirect_to dashboard_agencies_path, notice: "Agency branding saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path, alert: error.record.errors.full_messages.to_sentence
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
    redirect_to dashboard_agencies_path, notice: "Revenue terms saved for future purchases. Existing orders and subscriptions keep their agreed terms."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to dashboard_agencies_path, alert: error.message
  end
  def create_client
    agency = agency_scope.find(params[:id])
    values = params.require(:client).permit(:first_name, :last_name, :email_address)
    agency.agency_clients.create!(values.merge(role: "client", password: SecureRandom.urlsafe_base64(36)))
    redirect_to dashboard_agencies_path, notice: "Client account created. The client can use Forgot password to set their password."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_agencies_path, alert: error.record.errors.full_messages.to_sentence
  end
  private
  def require_agency_access!
    head :forbidden unless current_user&.role.in?(%w[super_admin white_label])
  end
  def agency_scope
    current_user.role == "super_admin" ? User.where(role: "white_label") : User.where(id: current_user.managed_account_ids, role: "white_label")
  end
end
