# frozen_string_literal: true
class Dashboard::CommercePayoutsController < Dashboard::SettingsHomeController
  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    @orders = LightekCommerce::Order.where(site: @site, status: "fulfilled")
      .includes(:refunds).order(created_at: :desc).limit(100)
  end

  def create
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    order = LightekCommerce::Order.where(site: site).find(params.require(:order_id))
    LightekCommerce::MerchantPayouts.request!(order: order, merchant: current_user)
    redirect_to dashboard_commerce_payouts_path(site_id: site.id),
      notice: "Funds transferred to your Stripe Connect account. Bank payout follows your Stripe schedule."
  rescue LightekCommerce::MerchantPayouts::Invalid, DymondBank::StripeService::StripeError,
      DymondBank::StripeService::ConfigurationError => e
    redirect_to dashboard_commerce_payouts_path(site_id: params[:site_id]), alert: e.message
  end
end
