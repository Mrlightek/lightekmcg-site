class IdentityChallengesController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check
  layout 'auth'
  protect_from_forgery with: :exception
  rate_limit to: 8, within: 3.minutes, only: :create
  before_action { response.headers['Cache-Control'] = 'no-store'; response.headers['Referrer-Policy'] = 'no-referrer' }
  def show
    pending!
  rescue LightekIdentity::Mfa::Invalid
    redirect_to new_session_path, alert: 'Sign in again to start a new verification.'
  end
  def create
    value = pending!
    user = User.find(value.fetch('user_id'))
    if value['connection_id']
      connection = LightekIdentity::Connection.find(value['connection_id'])
      raise LightekIdentity::Mfa::Invalid, 'Organization sign-in is disabled' unless connection.enabled?
      LightekIdentity::Oidc.active_member!(connection,user)
    end
    LightekIdentity::Mfa.verify!(user,params[:otp])
    session.delete(:mfa_pending)
    start_new_session_for(user,mfa_verified: true,identity_connection_id: value['connection_id'])
    redirect_to after_authentication_url
  rescue LightekIdentity::Mfa::Invalid, LightekIdentity::Oidc::Invalid, ActiveRecord::RecordNotFound => error
    redirect_to identity_challenge_path, alert: 'Verification failed or expired. Try a fresh code or sign in again.'
  end
  private
  def pending!
    value = session[:mfa_pending]&.stringify_keys
    raise LightekIdentity::Mfa::Invalid, 'Verification expired' unless value && value['expires_at'].to_i > Time.current.to_i
    value
  end
end
