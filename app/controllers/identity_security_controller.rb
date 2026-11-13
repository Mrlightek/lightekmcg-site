class IdentitySecurityController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :private_page
  rate_limit to: 8, within: 3.minutes, only: %i[enroll confirm disable]
  rescue_from LightekIdentity::Mfa::Invalid, with: ->(error) { redirect_to identity_security_path, alert: error.message }
  def show
    @enabled = LightekIdentity::Mfa.enabled?(current_user)
    @required = LightekIdentity::Mfa.required?(current_user)
  end
  def enroll
    password!
    @secret = LightekIdentity::Mfa.begin!(current_user)
    @uri = "otpauth://totp/#{ERB::Util.url_encode("Lightek:#{current_user.email_address}")}?secret=#{@secret}&issuer=Lightek&algorithm=SHA1&digits=6&period=30"
    render :enroll
  end
  def confirm
    @recovery_codes = LightekIdentity::Mfa.verify!(current_user,params[:otp],enrolling: true)
    Current.session.update!(mfa_verified_at: Time.current,mfa_enrollment_only: false)
    current_user.sessions.where.not(id: Current.session.id).delete_all
    render :recovery
  end
  def disable
    raise LightekIdentity::Mfa::Invalid, 'Your employer policy or privileged role requires an authenticator' if LightekIdentity::Mfa.required?(current_user)
    password!
    LightekIdentity::Mfa.verify!(current_user,params[:otp])
    LightekIdentity::Factor.find_by!(user: current_user).destroy!
    current_user.sessions.where.not(id: Current.session.id).delete_all
    redirect_to identity_security_path, notice: 'Authenticator disabled. Accounting workspaces require enrollment before further access.'
  end
  private
  def password!
    raise LightekIdentity::Mfa::Invalid, 'Enter your current password' unless current_user.authenticate(params[:password].to_s)
  end
  def private_page
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    head :forbidden if Current.session&.connect_delegation.present?
  end
end
