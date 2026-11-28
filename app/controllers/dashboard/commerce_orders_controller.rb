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
    return payment_receipt if params[:receipt_order_id].present?
    return packing_slips(params[:print_order_id]) if params[:print_order_id].present?
    return packing_slips(params.fetch(:packing_order_ids, [])) if params[:print_packing_slips] == '1'

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
  rescue LightekCommerce::OrderReport::Invalid, LightekCommerce::PackingSlips::Invalid => error
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

  def payment_receipt
    @order = paid_document_order(params[:receipt_order_id]).includes(:items).take!
    response.headers['Cache-Control'] = 'private, no-store'
    render 'commerce/payment_receipt', formats: [:html], layout: false
  end

  def packing_slips(ids)
    @slips = LightekCommerce::PackingSlips.for(site: @site, order_ids: ids)
    response.headers['Cache-Control'] = 'private, no-store'
    render :packing_slip, formats: [:html], layout: false
  end

  def paid_document_order(value)
    id = value.to_s
    raise ActiveRecord::RecordNotFound unless id.match?(/\A[1-9][0-9]{0,17}\z/)

    LightekCommerce::Order.receipt_eligible.where(site: @site, id: id)
  end
end
