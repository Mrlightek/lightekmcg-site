# frozen_string_literal: true
class Dashboard::CommerceOrdersController < Dashboard::CommerceBaseController
  def retry_provisioning
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params.require(:order_id))
    LightekCommerce::PaidInstanceProvisioningJob.enqueue_recovery!(order)
    redirect_to dashboard_commerce_orders_path(site_id: site.id), notice: "Existing customer installation queued for recovery."
  rescue LightekCommerce::PaidInstanceProvisioning::NotReady => error
    redirect_to dashboard_commerce_orders_path(site_id: site.id), alert: error.message
  end

  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    return packing_slip if params[:print_order_id].present?

    @filters = params.permit(*LightekCommerce::OrderReport::FILTERS)
    report = LightekCommerce::OrderReport.new(site: @site, filters: @filters)
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
    respond_to do |format|
      format.html { @orders = report.recent }
      format.csv do
        kind = params.fetch(:kind, 'orders')
        send_data report.csv(kind), filename: "commerce-#{kind}-#{Date.current.iso8601}.csv", type: 'text/csv; charset=utf-8'
      end
    end
  rescue LightekCommerce::OrderReport::Invalid => error
    redirect_to dashboard_commerce_orders_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def destroy
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params[:order_id])
    LightekCommerce::OrderRemoval.call(order)
    redirect_to dashboard_commerce_orders_path(site_id: site.id), notice: "Unpaid order ##{order.id} deleted.", status: :see_other
  rescue LightekCommerce::OrderRemoval::Invalid => error
    redirect_to dashboard_commerce_orders_path(site_id: site.id), alert: error.message, status: :see_other
  end

  def bulk_destroy
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    ids = Array(params[:order_ids]).map(&:to_s).reject(&:blank?).uniq
    if ids.empty? || ids.size > 150
      return redirect_to dashboard_commerce_orders_path(site_id: site.id), alert: "Select between 1 and 150 unpaid orders.", status: :see_other
    end
    # Resolve the entire selection in the authorized site before any mutation.
    orders = LightekCommerce::Order.visible.where(site: site).find(ids)
    removed = 0
    failures = []
    orders.each do |order|
      begin
        LightekCommerce::OrderRemoval.call(order)
        removed += 1
      rescue LightekCommerce::OrderRemoval::Invalid => error
        failures << "##{order.id}: #{error.message}"
      end
    end
    message = {notice: "#{removed} unpaid order(s) deleted."}
    message[:alert] = "#{failures.size} order(s) kept. #{failures.first(3).join(' ')}" if failures.any?
    redirect_to dashboard_commerce_orders_path(site_id: site.id), **message, status: :see_other
  end

  private

  def packing_slip
    order_id = params[:print_order_id].to_s
    raise ActiveRecord::RecordNotFound unless order_id.match?(/\A[1-9][0-9]{0,17}\z/)

    @order = LightekCommerce::Order.visible.where(site: @site, status: %w[paid fulfilled partially_refunded])
      .where.not(paid_at: nil).includes(:shipping_quote, items: :product).find(order_id)
    @packages = @order.items.select { |item| item.physical_for_fulfillment? }
    raise ActiveRecord::RecordNotFound if @packages.empty?

    @recipient = @order.shipping_quote&.shipment_payload.to_h.fetch('recipients', []).first
    response.headers['Cache-Control'] = 'private, no-store'
    render :packing_slip, formats: [:html], layout: false
  end
end
