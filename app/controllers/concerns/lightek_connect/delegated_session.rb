module LightekConnect
  module DelegatedSession
    extend ActiveSupport::Concern
    included do
      before_action :validate_connect_delegation!
    end
    private
    def connect_mfa_verified? = request.env['lightek.connect_mfa_verified'] == true
    def validate_connect_delegation!
      return if connect_mfa_verified?
      data = Current.session&.connect_delegation.to_h
      return if data.blank?
      if data["local"]
        connection = Connection.find_by(id: data["connection_id"], user: current_user, revoked_at: nil)
        allowed = connection && connection.user.role.in?(%w[white_label super_admin])
        if allowed
          grant = Grant.find_by!(id: data.fetch('grant_id'), connection: connection)
          proof = grant.mfa_context!
        end
      else
        site = DymondSite::Site.find_by!(host: request.host)
        allowed = current_user == site.tenant && current_user.role.in?(%w[client white_label]) &&
          Time.iso8601(data.fetch("expires_at")) > Time.current &&
          MfaHandoff.allowed_for?(current_user)
        if allowed
          result = LightekReservations::Federation::Client.new(site).request("connect/validate", method: :post,
            body: {connection_id: data.fetch('connection_id'), grant_id: data.fetch('grant_id'), controller_name: controller_path, action_name: action_name, method: request.method})
          allowed = result.fetch('allowed') == true
          allowed &&= result.fetch('owner_email') == current_user.email_address
          proof = result.fetch('delegation') if allowed
        end
      end
      if allowed
        MfaHandoff.validate_context!(proof, connection_id: data.fetch('connection_id'), grant_id: data.fetch('grant_id'))
        raise Gatekeeper::Hosting::Access::Denied, 'Management audience changed' unless proof['site_id'] == data['site_id'] && proof['actor'] == data['actor']
        Event.record!(connection, "dashboard_request", resource: proof['site_id'], details: {controller: controller_path, action: action_name, method: request.method, grant_id: grant.id, actor: proof['actor']}) if data["local"] && !request.get? && !request.head?
        request.env['lightek.connect_mfa_verified'] = true
        return
      end
      terminate_session
      head :unauthorized
    rescue KeyError, ArgumentError, TypeError, Gatekeeper::Hosting::Access::Denied, ActiveRecord::RecordNotFound, LightekReservations::Federation::Client::Unavailable
      terminate_session if Current.session
      head :unauthorized
    end
  end
end
