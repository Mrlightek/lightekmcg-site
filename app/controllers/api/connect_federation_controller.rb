class Api::ConnectFederationController < Api::ReservationFederationController
  rescue_from Gatekeeper::Hosting::Access::Denied, with: -> { head :forbidden }
  def redeem
    grant = LightekConnect::Grant.consume!(code: params.require(:code), site: @peer.site)
    render json: {owner_email: @peer.merchant.email_address,
      delegation: {connection_id: grant.connection_id, actor: grant.connection.user.email_address,
        site_id: @peer.site_id, expires_at: 1.hour.from_now.iso8601}}
  end
  def validate_session
    connection = LightekConnect::Connection.find_by(id: params[:connection_id], revoked_at: nil)
    allowed = connection && connection.user.role.in?(%w[white_label super_admin]) && LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: @peer.site_id)
    if allowed && request.post? && params[:action_name].present?
      LightekConnect::Event.record!(connection, "instance_request", resource: @peer.site_id,
        details: {controller: params[:controller_name].to_s.first(150), action: params[:action_name].to_s.first(80), method: params[:method].to_s.first(10)})
    end
    render json: {allowed: !!allowed}
  end
end
