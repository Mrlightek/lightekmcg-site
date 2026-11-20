class Dashboard::AgencyTrialsController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :private_response
  before_action :require_operator!, only: %i[index create resend publish]
  before_action :load_prospect_trial, only: %i[show update upgrade]
  rate_limit to: 5, within: 3.minutes, only: :resend

  rescue_from LightekAgency::Trial::Invalid, ActiveRecord::RecordInvalid,
    LightekCommerce::StripeCheckout::Unavailable, with: :invalid!

  def index
    @sites = LightekAgency::Trial.billing_sites(current_user).order(:name)
    @trials = LightekAgency::Trial.where(operator: current_user).includes(:prospect, :paid_order).order(created_at: :desc).limit(100)
  end

  def create
    fields = params.require(:trial)
    site = LightekAgency::Trial.billing_sites(current_user).find(fields.require(:billing_site_id))
    trial = LightekAgency::Trial.invite!(operator: current_user, billing_site: site,
      identity: fields.permit(:first_name, :last_name, :email_address).to_h.symbolize_keys,
      brand_name: fields[:brand_name], duration_days: fields[:duration_days])
    if trial.prospect.password_setup_invitation_error
      redirect_to dashboard_agency_trials_path, alert: 'Demo created. Use Send setup invitation to retry the email.'
    else
      redirect_to dashboard_agency_trials_path, notice: 'Agency demo created. The private setup invitation is queued.'
    end
  end

  def publish
    site = LightekAgency::Trial.billing_sites(current_user).find(params.require(:site_id))
    enabled = params[:enabled] == '1'
    site.with_lock do
      site.update!(manifest: site.manifest.to_h.merge(LightekAgency::Trial::PUBLIC_SITE_FLAG => enabled))
    end
    notice = enabled ? 'Public agency demo requests are open.' : 'Public agency demo requests are closed.'
    redirect_to dashboard_agency_trials_path, notice: notice, status: :see_other
  end

  def show; end

  def update
    @trial.with_lock do
      raise LightekAgency::Trial::Invalid, 'Your demo has ended.' unless @trial.preview_open?

      @trial.update!(params.require(:trial).permit(:brand_name, :sample_client_name, :sample_retail_dollars))
    end
    redirect_to dashboard_agency_trial_path(@trial), notice: 'Agency demo saved.'
  end

  def upgrade
    order = @trial.reserve_order!
    url = dashboard_agency_trial_url(@trial)
    checkout = LightekCommerce::StripeCheckout.start!(order: order, success_url: dashboard_agency_trial_url(@trial, checkout: 'returned'), cancel_url: url)
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  end

  def resend
    trial = LightekAgency::Trial.where(operator: current_user).find(params[:id])
    trial.prospect.send_password_setup_invitation!
    redirect_to dashboard_agency_trials_path, notice: 'Private setup invitation queued.'
  rescue ArgumentError => error
    redirect_to dashboard_agency_trials_path, alert: error.message
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Referrer-Policy'] = 'same-origin'
  end

  def require_operator!
    head :forbidden unless current_user.role == 'super_admin' && Current.session.connect_delegation.blank?
  end

  def load_prospect_trial
    raise ActiveRecord::RecordNotFound if Current.session.connect_delegation.present?

    @trial = LightekAgency::Trial.find_by!(id: params[:id], prospect: current_user)
  end

  def invalid!(error)
    path = @trial ? dashboard_agency_trial_path(@trial) : dashboard_agency_trials_path
    redirect_to path, alert: error.message, status: :see_other
  end
end
