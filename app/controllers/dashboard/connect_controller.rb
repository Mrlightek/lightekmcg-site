class Dashboard::ConnectController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role.in?(%w[white_label super_admin]) }
  before_action :load_sandboxes, only: %i[index create]
  def index
    @connections = LightekConnect::Connection.where(user: current_user).order(id: :desc)
  end
  def create
    @connection, @code = LightekConnect::Connection.issue!(user: current_user, platform: params.require(:platform), label: params.require(:label))
    @connections = LightekConnect::Connection.where(user: current_user).order(id: :desc)
    response.headers["Cache-Control"] = "no-store"
    render :index
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_connect_path, alert: error.record.errors.full_messages.to_sentence
  end
  def destroy
    LightekConnect::Connection.where(user: current_user).find(params[:id]).revoke!
    redirect_to dashboard_connect_path, notice: "Connection revoked."
  end
  private
  def load_sandboxes
    return unless current_user.role == "super_admin"
    @shopify_credentials_status = LightekConnect::ShopifyCredentials.status
    @sandbox_nodes = Gatekeeper::Hosting::Access.nodes(current_user).where.not(status: %w[provisioning deleting delete_failed decommissioned]).order(:name)
    @sandboxes = LightekConnect::Sandbox.order(id: :desc).limit(30)
  end
end
