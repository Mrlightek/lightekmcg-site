class Api::ConnectFederationController < Api::ReservationFederationController
  rescue_from Gatekeeper::Hosting::Access::Denied, with: -> { head :forbidden }
  def redeem
    grant = LightekConnect::Grant.consume!(code: params.require(:code), site: @peer.site, release_action: params[:release_action])
    render json: {owner_email: @peer.merchant.email_address,
      delegation: grant.mfa_context!, agency_editor: grant.connection.platform == 'dashboard' && params[:release_action].blank?,
      agency_release_action: params[:release_action]}
  end
  def validate_session
    connection = LightekConnect::Connection.find_by(id: params[:connection_id], revoked_at: nil)
    allowed = connection && connection.user.role.in?(%w[white_label super_admin]) && LightekSettings::WebsiteIdentity.sites_for(connection.user).exists?(id: @peer.site_id)
    allowed = false if connection&.platform == 'dashboard' && params[:grant_id].blank?
    if allowed && params[:grant_id].present?
      grant = LightekConnect::Grant.find_by!(id: params[:grant_id], connection: connection, site: @peer.site)
      if connection.platform == 'dashboard' && grant.destination != LightekConnect::AgencyDashboard::EDIT_DESTINATION
        raise Gatekeeper::Hosting::Access::Denied, 'Use an editor management grant'
      end
      context = grant.mfa_context!
    end
    if allowed && request.post? && params[:action_name].present?
      LightekConnect::Event.record!(connection, "instance_request", resource: @peer.site_id,
        details: {controller: params[:controller_name].to_s.first(150), action: params[:action_name].to_s.first(80), method: params[:method].to_s.first(10), grant_id: context&.fetch('grant_id'), actor: context&.fetch('actor')})
    end
    render json: {allowed: !!allowed, delegation: context, owner_email: @peer.merchant.email_address}
  end
end
