class ConnectManagementController < ApplicationController
  allow_unauthenticated_access
  protect_from_forgery with: :exception
  def show
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    @code = params.require(:code)
    raise ArgumentError unless @code.match?(/\A[0-9a-f]{64}\z/)
    # GET previews only. Browser prefetch must never consume a grant or establish a session.
  rescue ArgumentError
    head :bad_request
  end
  def create
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    site = DymondSite::Site.find_by(host: request.host)
    remote = LightekReservations::Federation::Client.config(site)
    if remote && remote["origin"].to_s.delete_suffix("/") != request.base_url
      raise Gatekeeper::Hosting::Access::Denied, "Unknown client instance" unless site
      data = LightekReservations::Federation::Client.new(site).request("connect/redeem", method: :post, body: {code: params.require(:code)})
      owner = site.tenant
      raise Gatekeeper::Hosting::Access::Denied, "Instance owner mismatch" unless owner.is_a?(User) && owner.email_address == data.fetch("owner_email") && owner.role.in?(%w[client white_label])
      delegation = data.fetch('delegation')
      LightekConnect::MfaHandoff.validate_context!(delegation, connection_id: delegation.fetch('connection_id'), grant_id: delegation.fetch('grant_id'))
      raise Gatekeeper::Hosting::Access::Denied, 'Company requires direct sign-in' unless LightekConnect::MfaHandoff.allowed_for?(owner)
      start_new_session_for(owner)
      Current.session.update!(connect_delegation: delegation)
      redirect_to "/dashboard"
    else
      raise Gatekeeper::Hosting::Access::Denied, "Open management at the central origin" unless request.base_url == LightekReservations::Federation::Issuer.origin
      candidate = LightekConnect::Grant.find_by!(code_digest: LightekConnect::Connection.digest(params.require(:code)))
      candidate.authorize_connection!
      raise Gatekeeper::Hosting::Access::Denied, 'Management grant expired' if candidate.consumed_at? || candidate.expires_at <= Time.current
      return unless verify_agency_browser!(candidate)
      candidate.approve!(Current.session)
      if candidate.site && (peer = LightekConnect::Workspace.new(candidate.connection).remote_peer(candidate.site))
        raise Gatekeeper::Hosting::Access::Denied, 'Client instance unavailable' unless peer.active?
        host = LightekSettings::SiteDomain.public_hostname!(candidate.site.host)
        return redirect_to("https://#{host}/connect/management?code=#{params.require(:code)}", allow_other_host: true)
      end
      grant = LightekConnect::Grant.consume!(code: params.require(:code), site: candidate.site)
      start_new_session_for(grant.connection.user)
      Current.session.update!(connect_delegation: grant.mfa_context!.merge('local' => true))
      redirect_to grant.destination
    end
  rescue ActiveRecord::RecordNotFound, KeyError, ArgumentError, TypeError, Gatekeeper::Hosting::Access::Denied, LightekReservations::Federation::Client::Unavailable
    head :forbidden
  end
  private
  def verify_agency_browser!(grant)
    resume_session
    return_to = "/connect/management?code=#{params.require(:code)}"
    unless Current.session && Current.session.connect_delegation.blank?
      session[:return_to_after_authenticating] = return_to
      # Do not let Sessions#new reuse an existing delegated identity as primary auth.
      cookies.delete(:session_id)
      Current.session = nil
      redirect_to main_app.new_session_path
      return false
    end
    raise Gatekeeper::Hosting::Access::Denied, 'Sign in as the connected agency account' unless Current.session.user_id == grant.connection.user_id
    return true if LightekConnect::MfaHandoff.source_verified?(Current.session, grant.connection.user)
    session[:return_to_after_authenticating] = return_to
    if LightekIdentity::Mfa.enabled?(current_user)
      session[:mfa_pending] = {'user_id' => current_user.id, 'connection_id' => Current.session.identity_connection_id, 'expires_at' => 5.minutes.from_now.to_i}
      redirect_to main_app.identity_challenge_path
    else
      redirect_to main_app.identity_security_path, alert: 'Set up and verify your agency authenticator before opening connected management.'
    end
    false
  end
end
