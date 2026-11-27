# frozen_string_literal: true
class Dashboard::CommerceProductsController < Dashboard::CommerceBaseController
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  before_action :set_site
  before_action :set_product, only: %i[edit update destroy]
  before_action :redirect_workspace_management, only: %i[edit update destroy]
  def index
    return inventory_history if params[:inventory_history] == '1'
    return inventory if params[:inventory] == '1'

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
    return import_inventory if params[:inventory_import] == '1'
    return move_inventory if params[:inventory_move] == '1'

    authorize_instance_product!
    @product = LightekCommerce::Product.new(product_params.except(:remove_photo_ids).merge(site: @site))
    return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product created." if @product.save
    render :new, status: :unprocessable_entity
  end
  def edit; end
  def update
    authorize_instance_product!
    attributes = product_params.except(:remove_photo_ids)
    if LightekCommerce::InventoryAdjustment.update_product!(product: @product, actor: current_user,
        attributes: attributes, version: params[:inventory_stock_version], reason: params[:inventory_reason])
      Array(product_params[:remove_photo_ids]).reject(&:blank?).each do |id|
        attachment = @product.photos_attachments.find_by(id: id)
        attachment&.purge
      end
      return redirect_to dashboard_commerce_products_path(site_id: @site.id), notice: "Product updated."
    end
    render :edit, status: :unprocessable_entity
  rescue LightekCommerce::InventoryAdjustment::Invalid => error
    redirect_to edit_dashboard_commerce_product_path(@product, site_id: @site.id), alert: error.message, status: :see_other
  end
  def destroy
    destination = dashboard_commerce_products_path(site_id: @site.id)
    @product.with_lock do
      if LightekCommerce::InventoryStockStates.allocated?(@product)
        return redirect_to destination, alert: 'Clear incoming, unavailable and damaged stock before removing this product.'
      end
      @product.destroy!
    end
    redirect_to destination, notice: "Product removed."
  end
  private
  def inventory
    @filters = params.permit(*LightekCommerce::InventoryReport::FILTERS)
    @inventory_report = LightekCommerce::InventoryReport.new(site: @site, filters: @filters)
    response.headers['Cache-Control'] = 'private, no-store'
    respond_to do |format|
      format.html do
        @inventory_rows = @inventory_report.rows(limit: 151)
        @more_inventory = @inventory_rows.length > 150
        @inventory_rows = @inventory_rows.first(150)
        render :inventory
      end
      format.csv do
        template = params[:adjustment_template] == '1'
        data = template ? @inventory_report.adjustment_csv : @inventory_report.csv
        prefix = template ? 'inventory-adjustment' : 'inventory'
        send_data data, filename: "#{prefix}-#{Date.current.iso8601}.csv", type: 'text/csv; charset=utf-8'
      end
    end
  rescue LightekCommerce::InventoryReport::Invalid => error
    redirect_to dashboard_commerce_products_path(site_id: @site.id, inventory: '1'), alert: error.message, status: :see_other
  end

  def inventory_history
    history = LightekCommerce::InventoryChange.for_site(@site).order(id: :desc)
    if params[:before].present?
      before = params[:before].to_s
      raise ActiveRecord::RecordNotFound unless before.match?(/\A[1-9][0-9]{0,17}\z/)

      history = history.where(id: ...before.to_i)
    end
    @inventory_changes = history.limit(101).to_a
    @more_inventory_changes = @inventory_changes.size > 100
    @inventory_changes = @inventory_changes.first(100)
    response.headers['Cache-Control'] = 'private, no-store'
    render :inventory_history, formats: [:html]
  end

  def move_inventory
    filters = params.permit(*LightekCommerce::InventoryReport::FILTERS).to_h
    destination = dashboard_commerce_products_path(filters.merge(site_id: @site.id, inventory: '1'))
    movement = params.expect(inventory_movement: %i[product_id variant_id movement quantity version])
    LightekCommerce::InventoryStockStates.move!(site: @site, actor: current_user, product_id: movement[:product_id],
      variant_id: movement[:variant_id], movement: movement[:movement], quantity: movement[:quantity], version: movement[:version])
    redirect_to destination, notice: 'Stock movement recorded.', status: :see_other
  rescue LightekCommerce::InventoryStockStates::Invalid => error
    redirect_to destination, alert: error.message, status: :see_other
  end

  def import_inventory
    file = params[:inventory_csv]
    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      raise LightekCommerce::InventoryAdjustment::Invalid, 'Choose an inventory adjustment CSV.'
    end

    data = file.read(LightekCommerce::InventoryAdjustment::MAX_BYTES + 1).to_s.force_encoding(Encoding::UTF_8)
    count = LightekCommerce::InventoryAdjustment.apply!(site: @site, actor: current_user, data: data, reason: params[:inventory_reason])
    redirect_to dashboard_commerce_products_path(site_id: @site.id, inventory: '1'),
      notice: "Updated #{count} inventory #{'row'.pluralize(count)}.", status: :see_other
  rescue LightekCommerce::InventoryAdjustment::Invalid => error
    redirect_to dashboard_commerce_products_path(site_id: @site.id, inventory: '1'), alert: error.message, status: :see_other
  end

  def redirect_workspace_management
    return unless @product.hosting_package && Gatekeeper::Hosting::WorkspacePlans.workspace?(@product)

    raise CanCan::AccessDenied unless current_user.role == "super_admin"

    redirect_to dashboard_hosting_packages_path, notice: "Manage Workspace pricing and availability in Hosting packages."
  end

  def authorize_instance_product!
    requested_type = params.fetch(:product, {})[:product_type].to_s
    is_installation = requested_type == "lightek_instance" || @product&.product_type == "lightek_instance"
    raise CanCan::AccessDenied if is_installation && current_user.role != "super_admin" && !@product&.source_hosting_package_id
  end
  def set_site
    sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = sites.find(params.require(:site_id))
  end
  def set_product
    @product = LightekCommerce::Product.where(site: @site).find(params[:id])
  end
  def product_params
    params.require(:product).permit(:shipping_weight_lb, :shipping_length_in, :shipping_width_in, :shipping_height_in, :name, :slug, :description, :price_cents, :inventory_quantity, :published, :position, :image_url, :sku, :product_type, :billing_interval, :track_inventory, :short_description, :compare_at_cents, :featured, :subscription_plan_id, photos: [], remove_photo_ids: [])
  end
end
