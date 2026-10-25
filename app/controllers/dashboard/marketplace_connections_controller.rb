# frozen_string_literal: true
class Dashboard::MarketplaceConnectionsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_marketplace_admin!
  before_action :set_connection, only: %i[edit update]
  protect_from_forgery with: :exception
  def index
    @connections = LightekMarketplace::CustomerService.order(:name, :id)
  end
  def new
    @connection = LightekMarketplace::CustomerService.new
  end
  def create
    @connection = LightekMarketplace::CustomerService.new(connection_params)
    persist(:new)
  end
  def edit; end
  def update
    @connection.assign_attributes(connection_params)
    persist(:edit)
  end
  private
  def persist(template)
    if @connection.active?
      @connection.reviewed_by_id = current_user.id
      @connection.reviewed_at = Time.current
    else
      @connection.reviewed_by_id = nil
      @connection.reviewed_at = nil
    end
    if @connection.save
      redirect_to main_app.dashboard_marketplace_connections_path, notice: "Application connection saved."
    else
      render template, status: :unprocessable_entity
    end
  end
  def set_connection
    @connection = LightekMarketplace::CustomerService.find(params[:id])
  end
  def connection_params
    params.require(:customer_service).permit(:name, :description, :feature_key, :customer_path, :active)
  end
  def require_marketplace_admin!
    head :forbidden unless current_user&.role == "super_admin"
  end
end
