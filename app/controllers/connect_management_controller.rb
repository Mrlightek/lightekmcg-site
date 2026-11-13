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
      start_new_session_for(owner)
      Current.session.update!(connect_delegation: data.fetch("delegation"))
      redirect_to "/dashboard"
    else
      raise Gatekeeper::Hosting::Access::Denied, "Open management at the central origin" unless request.base_url == LightekReservations::Federation::Issuer.origin
      candidate = LightekConnect::Grant.find_by!(code_digest: LightekConnect::Connection.digest(params.require(:code)))
      if candidate.site && LightekConnect::Workspace.new(candidate.connection).remote_peer(candidate.site)
        raise Gatekeeper::Hosting::Access::Denied, "Open management on the client instance"
      end
      grant = LightekConnect::Grant.consume!(code: params.require(:code), site: candidate.site)
      start_new_session_for(grant.connection.user)
      Current.session.update!(connect_delegation: {"connection_id" => grant.connection_id, "local" => true})
      redirect_to grant.destination
    end
  rescue ActiveRecord::RecordNotFound, ArgumentError, Gatekeeper::Hosting::Access::Denied, LightekReservations::Federation::Client::Unavailable
    head :forbidden
  end
end
