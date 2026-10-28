# frozen_string_literal: true
class Dashboard::CommerceFulfillmentsController < Dashboard::SettingsHomeController
  def create
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params.require(:order_id))
    LightekCommerce::Fulfillment.complete!(order: order,
      reference: params[:fulfillment_reference], note: params[:fulfillment_note])
    redirect_to dashboard_commerce_orders_path(site_id: site.id), notice: "Order fulfilled. Customer notification queued."
  rescue LightekCommerce::Fulfillment::Invalid => e
    redirect_to dashboard_commerce_orders_path(site_id: params[:site_id]), alert: e.message
  end
end
