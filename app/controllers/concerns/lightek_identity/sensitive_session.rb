module LightekIdentity
  module SensitiveSession
    extend ActiveSupport::Concern
    private
    def require_sensitive_session!
      return head(:forbidden) unless current_user && Current.session
      if Current.session.connect_delegation.present?
        return head(:forbidden) unless connect_mfa_verified?
        return
      end
      unless Mfa.enabled?(current_user)
        return redirect_to(main_app.identity_security_path,alert: 'Enable an authenticator before accessing financial or security-sensitive features.')
      end
      unless Mfa.fresh?(Current.session)
        session[:mfa_pending] = {'user_id'=>current_user.id,'connection_id'=>Current.session.identity_connection_id,'expires_at'=>5.minutes.from_now.to_i}
        return redirect_to(main_app.identity_challenge_path)
      end
    end
  end
end
