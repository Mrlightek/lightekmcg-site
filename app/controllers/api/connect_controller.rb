class Api::ConnectController < ActionController::Base
  rescue_from LightekConnect::ShopifyCredentials::Unavailable, with: ->(error) { render json: {error: error.message}, status: :service_unavailable }
  skip_forgery_protection
  before_action :secure_transport!
  before_action :authenticate_connection!, except: :pair
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: {error: "Resource not found"}, status: :not_found }
  rescue_from LightekConnect::InstanceTransport::Unavailable, with: ->(e) { render json: {error: e.message}, status: :bad_gateway }
  rescue_from LightekConnect::Shopify::Invalid, with: -> { head :unauthorized }
  rescue_from Gatekeeper::Hosting::Access::Denied, with: ->(e) { render json: {error: e.message}, status: :forbidden }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, ActionController::ParameterMissing, with: -> { render json: {error: "Invalid request"}, status: :unprocessable_entity }
  def pair
    platform = params.require(:platform)
    identity = platform == "shopify" ? LightekConnect::Shopify.identity!(request.authorization) : nil
    connection, token = LightekConnect::Connection.redeem!(code: params.require(:code), platform: platform, identity: identity)
    render json: {token: platform == "wordpress" ? token : nil, connection_id: connection.id}
  end
  def show
    render json: workspace.snapshot
  end
  def update_site
    render json: workspace.rename!(params[:id], params.require(:name))
  end
  def management
    render json: workspace.management!(params[:id])
  end
  def dashboard
    allowed = workspace.snapshot.fetch(:capabilities).map { |item| item.fetch(:path) }
    path = params[:path].presence || allowed.first
    raise ArgumentError unless allowed.include?(path)
    code = LightekConnect::Grant.issue!(connection: @connection, site: nil, destination: path)
    render json: {url: "#{LightekReservations::Federation::Issuer.origin}/connect/management?code=#{code}", expires_in: 60, external: true}
  end
  def disconnect
    @connection.revoke!
    head :no_content
  end
  private
  def workspace = LightekConnect::Workspace.new(@connection)
  def secure_transport!
    response.headers["Cache-Control"] = "no-store"
    head :upgrade_required if Rails.env.production? && !request.ssl?
  end
  def authenticate_connection!
    token = request.authorization.to_s.delete_prefix("Bearer ")
    if token.count(".") == 2
      identity = LightekConnect::Shopify.identity!(request.authorization)
      @connection = LightekConnect::Connection.where(platform: "shopify", external_identity: identity, revoked_at: nil).where.not(token_digest: nil).order(id: :desc).first
      @connection = nil unless @connection&.user&.role.in?(%w[white_label super_admin])
    else
      @connection = LightekConnect::Connection.authenticate(token)
      @connection = nil unless @connection&.platform == "wordpress"
    end
    head :unauthorized unless @connection
  rescue LightekConnect::Shopify::Invalid
    head :unauthorized
  end
end
