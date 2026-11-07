# frozen_string_literal: true
class Dashboard::CommerceProductsController < Dashboard::SettingsHomeController
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  before_action :set_site
  before_action :set_product, only: %i[edit update destroy]
  def index
    @products = LightekCommerce::Product.where(site: @site).order(:position, :id)
  end
  def preview_industry
    document = LightekDesign::StudioDocument.normalize(LightekCommerce::IndustryStarters.document(params.require(:industry), site: @site))
    @preview = true
    @design_key = "industry_preview"
    @design = LightekDesign::StudioDocument.definition_for(document, key: @design_key, document_id: 0, version: 0)
    @studio_preview_definition = @design
    @page = Struct.new(:title).new(document["name"])
    response.set_header("Cache-Control", "private, no-store")
    render "lightek_design/preview", layout: "lightek_design/website"
  rescue KeyError
    raise ActiveRecord::RecordNotFound
  end

  def install_industry
    LightekCommerce::IndustryStarters.install!(site: @site, industry: params.require(:industry), user: current_user)
    redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Complete shop design saved to Design Studio and a draft page. Edit and publish it in Pages & Sections."
  rescue KeyError
    redirect_to dashboard_commerce_products_path(site_id: @site.id), alert: "Unknown industry."
  end
  def create_shop_page
    page = LightekCommerce::StarterPage.create!(site: @site)
    redirect_to dashboard_commerce_products_path(site_id: @site.id),
      notice: "Draft shop page #{page.title} created in Pages & Sections."
  end
  def new
    @product = LightekCommerce::Product.new(site: @site)
  end
  def create
    authorize_instance_product!
    @product = LightekCommerce::Product.new(product_params.except(:remove_photo_ids).merge(site: @site))
    return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product created." if @product.save
    render :new, status: :unprocessable_entity
  end
  def edit; end
  def update
    authorize_instance_product!
    if @product.update(product_params.except(:remove_photo_ids))
      Array(product_params[:remove_photo_ids]).reject(&:blank?).each do |id|
        attachment = @product.photos_attachments.find_by(id: id)
        attachment&.purge
      end
      return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product updated."
    end
    render :edit, status: :unprocessable_entity
  end
  def destroy
    @product.destroy!
    redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product removed."
  end
  private
  def authorize_instance_product!
    requested_type = params.fetch(:product, {})[:product_type].to_s
    is_installation = requested_type == "lightek_instance" || @product&.product_type == "lightek_instance"
    raise CanCan::AccessDenied if is_installation && current_user.role != "super_admin"
  end
  def set_site
    sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = sites.find(params.require(:site_id))
  end
  def set_product
    @product = LightekCommerce::Product.where(site: @site).find(params[:id])
  end
  def product_params
    params.require(:product).permit(:name, :slug, :description, :price_cents, :inventory_quantity, :published, :position, :image_url, :sku, :product_type, :short_description, :compare_at_cents, :featured, :subscription_plan_id, photos: [], remove_photo_ids: [])
  end
end
