# frozen_string_literal: true

class Dashboard::CommerceSupplierOrdersController < Dashboard::CommerceBaseController
  before_action :set_site
  before_action :set_order, only: %i[show change]

  def index
    @orders = LightekCommerce::SupplierOrder.where(site: @site).order(id: :desc)
    @orders = @orders.where(id: ...params[:before].to_i) if params[:before].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
    @orders = @orders.limit(51).to_a
    @older = @orders.pop if @orders.size > 50
  end

  def create
    values = params.expect(supplier_order: %i[supplier expected_on])
    expected = values[:expected_on].presence
    if expected && !valid_date?(expected)
      return redirect_to dashboard_commerce_supplier_orders_path(site_id: @site.id),
        alert: 'Enter a valid expected delivery date.', status: :see_other
    end
    order = LightekCommerce::SupplierOrder.create!(site: @site, supplier: values[:supplier].to_s.strip, expected_on: expected)
    redirect_to dashboard_commerce_supplier_order_path(order, site_id: @site.id), notice: 'Draft purchase order created.', status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dashboard_commerce_supplier_orders_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  def show
    @lines = @order.lines.order(:id).to_a
    return unless @order.status == 'draft'

    @lookup = params[:lookup].to_s.strip.first(120)
    report = LightekCommerce::InventoryReport.new(site: @site, filters: {stock: 'all', lookup: @lookup, include_drafts: '1'})
    @choices = report.rows(limit: 151, adjustable: true, physical_only: true)
    @more_choices = @choices.pop if @choices.size > 150
  end

  def change
    service = LightekCommerce::SupplierOrders.new(order: @order, actor: current_user)
    notice = case params[:operation]
    when 'save_line'
      service.save_line!(item_key: params[:item_key], quantity: params[:quantity], unit_cost: params[:unit_cost])
      'Purchase order item saved.'
    when 'remove_line'
      service.remove_line!(line_id: params[:line_id])
      'Purchase order item removed.'
    when 'place'
      service.place!
      'Purchase order marked as ordered. Incoming stock updated.'
    when 'receive'
      service.receive!(line_id: params[:line_id], quantity: params[:quantity], expected_received: params[:expected_received])
      'Receipt recorded and available stock updated.'
    when 'cancel'
      service.cancel!
      'Purchase order canceled. Outstanding supplier stock cleared.'
    when 'invoice'
      service.reconcile_invoice!(reference: params[:reference], subtotal: params[:subtotal])
      'Invoice subtotal recorded.'
    else
      raise ActionController::BadRequest
    end
    redirect_to order_path, notice: notice, status: :see_other
  rescue LightekCommerce::SupplierOrders::Invalid, LightekCommerce::InventoryStockStates::Invalid => error
    redirect_to order_path, alert: error.message, status: :see_other
  end

  private

  def valid_date?(value)
    value = value.to_s
    value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/) && Date.iso8601(value).year.positive?
  rescue ArgumentError
    false
  end

  def set_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end

  def set_order
    @order = LightekCommerce::SupplierOrder.where(site: @site).find(params[:id])
  end

  def order_path
    dashboard_commerce_supplier_order_path(@order, site_id: @site.id)
  end
end
