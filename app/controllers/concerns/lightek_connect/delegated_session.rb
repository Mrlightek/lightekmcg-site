module LightekConnect
  module DelegatedSession
    extend ActiveSupport::Concern
    included do
      before_action :validate_connect_delegation!
    end
    private
    def validate_connect_delegation!
      data = Current.session&.connect_delegation.to_h
      return if data.blank?
      if data["local"]
        connection = Connection.find_by(id: data["connection_id"], user: current_user, revoked_at: nil)
        allowed = connection && connection.user.role.in?(%w[white_label super_admin])
      else
        site = DymondSite::Site.find_by!(host: request.host)
        allowed = Time.iso8601(data.fetch("expires_at")) > Time.current &&
          LightekReservations::Federation::Client.new(site).request("connect/validate", method: :post,
            body: {connection_id: data["connection_id"], controller_name: controller_path, action_name: action_name, method: request.method}).fetch("allowed") == true
      end
      if allowed
        Event.record!(connection, "dashboard_request", details: {controller: controller_path, action: action_name, method: request.method}) if data["local"] && !request.get? && !request.head?
        return
      end
      terminate_session
      head :unauthorized
    rescue KeyError, ArgumentError, ActiveRecord::RecordNotFound, LightekReservations::Federation::Client::Unavailable
      terminate_session if Current.session
      head :unauthorized
    end
  end
end
