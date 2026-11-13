class IdentitySsoController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check
  protect_from_forgery with: :exception
  rate_limit to: 12, within: 3.minutes, only: :create
  before_action { response.headers['Cache-Control'] = 'no-store'; response.headers['Referrer-Policy'] = 'no-referrer' }
  def create
    connection = LightekIdentity::Connection.find_by!(slug: params[:organization], enabled: true)
    linking_user = nil
    if params[:link] == '1'
      resume_session
      raise LightekIdentity::Oidc::Invalid, 'Sign in locally and re-enter your password before linking' unless current_user && current_user.authenticate(params[:password].to_s) && Current.session.connect_delegation.blank?
      raise LightekIdentity::Oidc::Invalid, 'Verify your authenticator before linking' unless LightekIdentity::Mfa.enabled?(current_user) && LightekIdentity::Mfa.fresh?(Current.session)
      linking_user = current_user
    end
    session[:oidc_browser] ||= SecureRandom.hex(32)
    url = LightekIdentity::Oidc.start!(connection: connection, browser: session[:oidc_browser], redirect_uri: identity_sso_callback_url, linking_user: linking_user)
    redirect_to url, allow_other_host: true
  rescue ActiveRecord::RecordNotFound, LightekIdentity::Oidc::Invalid
    redirect_to new_session_path, alert: 'Organization sign-in unavailable. Sign in locally to manage your identity.'
  end
  def callback
    resume_session
    user, connection, linked = LightekIdentity::Oidc.finish!(state: params[:state], code: params[:code], browser: session[:oidc_browser], current_actor: current_user)
    if linked
      redirect_to identity_security_path, notice: 'Organization identity linked. Email matching does not grant or change permissions.'
    else
      complete_primary_authentication_for(user,identity_connection_id: connection.id)
    end
  rescue LightekIdentity::Oidc::Invalid, LightekIdentity::PublicHttp::Invalid
    redirect_to new_session_path, alert: 'Organization sign-in could not be verified. Use local sign-in or contact your administrator.'
  end
end
