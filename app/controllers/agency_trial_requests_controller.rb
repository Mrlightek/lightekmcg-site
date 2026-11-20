class AgencyTrialRequestsController < ApplicationController
  allow_unauthenticated_access
  layout 'auth'
  protect_from_forgery with: :exception
  rate_limit to: 10, within: 10.minutes, only: :create
  before_action :load_site
  before_action :load_trial_request, only: %i[show activate]

  rescue_from LightekAgency::Trial::Invalid, ActiveRecord::RecordInvalid, with: :invalid!
  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: :invalid_confirmation!

  def new; end

  def create
    values = params.require(:trial_request).permit(:first_name, :last_name, :email_address)
    email = values[:email_address].to_s.strip.downcase
    if params[:website_url].blank?
      trial_request = @site.with_lock do
        operator = LightekAgency::Trial.public_operator(@site)
        raise ActiveRecord::RecordNotFound unless operator
        scope = LightekAgency::TrialRequest.where(site: @site, email_address: email)
        next if scope.where('created_at > ?', 1.hour.ago).exists?

        scope.create!(operator: operator, first_name: values[:first_name], last_name: values[:last_name])
      end
      queue_confirmation!(trial_request) if trial_request
    end
    redirect_to request_agency_demo_path, notice: 'Check your email for a private link to start your agency demo.', status: :see_other
  end

  def show; end

  def activate
    trial, needs_password = @trial_request.confirm!
    if trial && needs_password
      redirect_to edit_account_setup_path(trial.prospect.generate_token_for(:password_setup)), status: :see_other
    elsif trial
      redirect_to dashboard_agency_trial_path(trial), status: :see_other
    else
      redirect_to new_session_path, alert: 'Contact Lightek support to request an agency demo for this account.', status: :see_other
    end
  end

  private

  def load_site
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Referrer-Policy'] = 'same-origin'
    @site = DymondSite::Site.find_by!(host: request.host.downcase)
    raise ActiveRecord::RecordNotFound unless LightekAgency::Trial.public_site?(@site)
  end

  def load_trial_request
    @trial_request = LightekAgency::TrialRequest.find_by_token_for!(:confirmation, params[:token])
    raise ActiveRecord::RecordNotFound unless @trial_request.site_id == @site.id && @trial_request.available?
  end

  def queue_confirmation!(trial_request)
    job = LightekAgency::DemoRequestMailer.agency_trial_confirmation(trial_request.id).deliver_later
    raise LightekAgency::Trial::Invalid, 'Email is temporarily unavailable. Please try again.' unless job
  rescue ActiveJob::EnqueueError, LightekAgency::Trial::Invalid
    trial_request.destroy!
    raise LightekAgency::Trial::Invalid, 'Email is temporarily unavailable. Please try again.'
  end

  def invalid!(_error)
    redirect_to request_agency_demo_path, alert: 'We could not process this request. Check your details and try again.', status: :see_other
  end

  def invalid_confirmation!(_error)
    redirect_to request_agency_demo_path, alert: 'That confirmation link is invalid or expired. Request a fresh link.', status: :see_other
  end
end
