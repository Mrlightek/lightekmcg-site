module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      if resume_session
        return if controller_name == 'sessions' && action_name == 'destroy'
        enrollment_route = controller_name == 'identity_security' || (controller_name == 'sessions' && action_name == 'destroy')
        if LightekIdentity::Mfa.required?(Current.session.user) && !LightekIdentity::Mfa.enabled?(Current.session.user)
          Current.session.update!(mfa_enrollment_only: true) unless Current.session.mfa_enrollment_only?
          return if enrollment_route
          return redirect_to(main_app.identity_security_path)
        end
        if Current.session.mfa_enrollment_only? && !enrollment_route
          return redirect_to(main_app.identity_security_path)
        end
        if LightekIdentity::Mfa.enabled?(Current.session.user) && !LightekIdentity::Mfa.fresh?(Current.session)
          session[:mfa_pending] = {'user_id'=>Current.session.user_id, 'connection_id'=>Current.session.identity_connection_id, 'expires_at'=>5.minutes.from_now.to_i}
          redirect_to main_app.identity_challenge_path
        end
      else
        request_authentication
      end
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      candidate = Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
      return unless candidate
      if candidate.identity_connection_id
        connection = LightekIdentity::Connection.find_by(id: candidate.identity_connection_id, enabled: true)
        return unless connection
        LightekIdentity::Oidc.active_member!(connection,candidate.user)
      end
      candidate
    rescue LightekIdentity::Oidc::Invalid
      nil
    end

  def request_authentication
  session[:return_to_after_authenticating] = request.url
  redirect_to main_app.new_session_path     # was: new_session_path
end

    def after_authentication_url
  session.delete(:return_to_after_authenticating) || case Current.session&.user&.role
  when "white_label" then main_app.dashboard_agencies_url
  when "client" then main_app.dashboard_servers_url
  else main_app.dashboard_nevaeh_os_url
  end
end

    def complete_primary_authentication_for(user, identity_connection_id: nil)
      if LightekIdentity::Mfa.enabled?(user)
        session[:mfa_pending] = {'user_id'=>user.id, 'connection_id'=>identity_connection_id, 'expires_at'=>5.minutes.from_now.to_i}
        redirect_to main_app.identity_challenge_path
      elsif LightekIdentity::Mfa.required?(user)
        start_new_session_for(user,identity_connection_id: identity_connection_id,mfa_enrollment_only: true)
        redirect_to main_app.identity_security_path
      else
        start_new_session_for(user,identity_connection_id: identity_connection_id)
        redirect_to after_authentication_url
      end
    end

    def start_new_session_for(user, mfa_verified: false, identity_connection_id: nil, mfa_enrollment_only: false)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip, identity_connection_id: identity_connection_id, mfa_enrollment_only: mfa_enrollment_only, mfa_verified_at: (Time.current if mfa_verified)).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax, secure: Rails.env.production? }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
