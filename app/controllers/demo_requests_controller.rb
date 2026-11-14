class DemoRequestsController < ApplicationController
  allow_unauthenticated_access
  layout 'auth'
  protect_from_forgery with: :exception
  rate_limit to: 3, within: 1.hour, only: :create
  before_action { response.headers['Cache-Control'] = 'no-store, private'; response.headers['Referrer-Policy'] = 'same-origin' }
  before_action :load_public_agency
  rescue_from LightekAgency::Demos::Invalid, ActiveRecord::RecordInvalid, with: :invalid!
  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: ->(_) { redirect_to request_demo_path, alert: 'Demo confirmation link is invalid or expired. Request another demo.' }
  def new; end
  def create
    values = params.require(:demo_request).permit(:first_name, :last_name, :email_address).to_h
    values['email_address'] = values['email_address'].to_s.strip.downcase
    if params[:website_url].blank? && !LightekAgency::DemoRequest.where(agency: @setting.agency, email_address: values['email_address']).where('invitation_queued_at > ?', 1.hour.ago).exists?
      record = LightekAgency::DemoRequest.create!(values.merge(agency: @setting.agency))
      LightekAgency::DemoRequestMailer.confirmation(record.id).deliver_later
      record.update!(invitation_queued_at: Time.current)
    end
    redirect_to request_demo_path, notice: 'Check your email for a private confirmation link. After confirmation, your demo is created automatically.'
  end
  def show
    load_request
  end
  def activate
    load_request
    resume_session
    existing = User.find_by(email_address: @demo_request.email_address)
    if existing && current_user != existing
      return redirect_to new_session_path(return_to: confirm_demo_request_path(params[:token])), alert: 'Sign in to confirm the demo for your existing account.'
    end
    demo = nil
    @demo_request.with_lock do
      raise LightekAgency::Demos::Invalid, 'This confirmation was already used' unless @demo_request.status == 'pending' && @demo_request.expires_at > Time.current
      demo = LightekAgency::Demos.create!(agency: @setting.agency, request: @demo_request, existing_client: existing,
        values: @demo_request.attributes.slice('first_name', 'last_name', 'email_address').symbolize_keys)
    end
    if demo.client.password_setup_required?
      redirect_to edit_account_setup_path(demo.client.generate_token_for(:password_setup))
    else
      redirect_to dashboard_demo_path(demo), notice: 'Your demo is ready.'
    end
  end
  private
  def load_public_agency
    @setting = LightekAgency::Demos.public_setting(request.host)
  end
  def load_request
    @demo_request = LightekAgency::DemoRequest.find_by_token_for!(:confirmation, params[:token])
    raise ActiveRecord::RecordNotFound unless @demo_request.agency_id == @setting.agency_id
    raise LightekAgency::Demos::Invalid, 'Demo confirmation expired' unless @demo_request.expires_at > Time.current
  end
  def invalid!(error)
    redirect_to request_demo_path, alert: error.message, status: :see_other
  end
end
