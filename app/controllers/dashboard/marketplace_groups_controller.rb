# frozen_string_literal: true
class Dashboard::MarketplaceGroupsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_marketplace_admin!
  before_action :set_group, only: %i[edit update]
  protect_from_forgery with: :exception
  def index
    @groups = LightekMarketplace::ProductGroup.order(:position, :id)
    @counts = DymondCatalog::MarketplaceListing.group(:category).count
  end
  def new
    @group = LightekMarketplace::ProductGroup.new
  end
  def create
    @group = LightekMarketplace::ProductGroup.new(group_params)
    if @group.save
      redirect_to main_app.dashboard_marketplace_groups_path, notice: "Product group created."
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit; end
  def update
    if @group.update(group_params)
      redirect_to main_app.dashboard_marketplace_groups_path, notice: "Product group updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  private
  def set_group
    @group = LightekMarketplace::ProductGroup.find(params[:id])
  end
  def group_params
    params.require(:product_group).permit(:name, :description, :position, :active)
  end
  def require_marketplace_admin!
    head :forbidden unless current_user&.role == "super_admin"
  end
end
