# frozen_string_literal: true
class Dashboard::CommerceProductsController < Dashboard::SettingsHomeController
  before_action :set_site
  before_action :set_product, only: %i[edit update destroy]
  def index
    @products = LightekCommerce::Product.where(site: @site).order(:position, :id)
  end
  def new
    @product = LightekCommerce::Product.new(site: @site)
  end
  def create
    @product = LightekCommerce::Product.new(product_params.merge(site: @site))
    return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product created." if @product.save
    render :new, status: :unprocessable_entity
  end
  def edit; end
  def update
    return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product updated." if @product.update(product_params)
    render :edit, status: :unprocessable_entity
  end
  def destroy
    @product.destroy!
    redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product removed."
  end
  private
  def set_site
    sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = sites.find(params.require(:site_id))
  end
  def set_product
    @product = LightekCommerce::Product.where(site: @site).find(params[:id])
  end
  def product_params
    params.require(:product).permit(:name, :slug, :description, :price_cents, :inventory_quantity, :published, :position)
  end
end
