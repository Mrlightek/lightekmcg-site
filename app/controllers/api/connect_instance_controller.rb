class Api::ConnectInstanceController < ActionController::Base
  skip_forgery_protection
  def update
    response.headers["Cache-Control"] = "no-store"
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    site = DymondSite::Site.find_by!(host: request.host)
    config = LightekReservations::Federation::Client.config(site)
    return head :forbidden unless config && site.tenant.is_a?(User) && site.tenant.role.in?(%w[client white_label])
    secret = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"), consumer: LightekReservations::Federation::Client::CONSUMER,
      purpose: "reservation_federation", requested_by: "lightek-connect")
    token = request.authorization.to_s.delete_prefix("Bearer ")
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(secret.fetch("token"), token)
    allowed = LightekReservations::Federation::Client.new(site).request("connect/validate", method: :post,
      body: {connection_id: params.require(:connection_id), controller_name: controller_path, action_name: action_name, method: request.method})
    return head :forbidden unless allowed["allowed"] == true
    name = params.require(:name)
    raise ArgumentError unless name.is_a?(String) && name.strip.length.between?(1, 160)
    LightekSettings::WebsiteIdentity.rename!(site: site, name: name)
    render json: {host: site.host, name: site.reload.name, verified: site.name == name.strip}
  rescue ActiveRecord::RecordNotFound, KeyError, ArgumentError, ActionController::ParameterMissing, ActiveRecord::RecordInvalid
    render json: {error: "Invalid instance request"}, status: :unprocessable_entity
  rescue LightekReservations::Federation::Client::Unavailable
    head :service_unavailable
  ensure
    secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end
end
