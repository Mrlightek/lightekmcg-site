# frozen_string_literal: true
class Dashboard::CommerceRefundsController < Dashboard::SettingsHomeController
  def create
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params[:order_id])
    LightekCommerce::Refunds.issue!(order: order, amount_cents: params.require(:amount_cents))
    redirect_to dashboard_commerce_orders_path(site_id: site.id), notice: "Refund request submitted; check processor status."
  rescue LightekCommerce::Refunds::Invalid, Stripe::StripeError => e
    redirect_to dashboard_commerce_orders_path(site_id: params[:site_id]), alert: e.message
  end
end
