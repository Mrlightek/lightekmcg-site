# frozen_string_literal: true
class Dashboard::CommerceOrdersController < Dashboard::SettingsHomeController
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
    @orders = LightekCommerce::Order.where(site: @site).includes(:items).order(created_at: :desc).limit(150)
  end
end
