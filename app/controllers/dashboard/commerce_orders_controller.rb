# frozen_string_literal: true
class Dashboard::CommerceOrdersController < Dashboard::CommerceBaseController
  def retry_provisioning
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params.require(:order_id))
    raise ActiveRecord::RecordNotFound unless order.paid_at? && order.items.any? { |item| item.product.product_type == "lightek_instance" }
    raise ActiveRecord::RecordNotFound if order.provisioned_at?
    LightekCommerce::PaidInstanceProvisioningJob.perform_later(order.id)
    redirect_to dashboard_commerce_orders_path(site_id: site.id), notice: "Existing customer installation queued for recovery."
  end

  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    @orders = LightekCommerce::Order.visible.where(site: @site).includes(items: :product).order(created_at: :desc).limit(150)
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
end
