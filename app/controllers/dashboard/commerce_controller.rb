class Dashboard::CommerceController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role.in?(%w[super_admin admin white_label client]) }
  def index
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first
    return unless @site
    @earned_shares = LightekCommerce::RevenueAllocation.where(beneficiary: current_user).includes(:order).order(id: :desc).limit(100)
    @products = LightekCommerce::Product.where(site: @site)
    orders = LightekCommerce::Order.where(site: @site)
    @paid_count = orders.where(status: %w[paid fulfilled partially_refunded]).count
    @revenue = orders.where(status: %w[paid fulfilled partially_refunded refunded]).sum("total_cents - refunded_cents")
    @awaiting_fulfillment = orders.where(status: "paid").count
    @subscriptions = LightekCommerce::Subscription.for_sites(DymondSite::Site.where(id: @site.id)).includes(:order, :billing_invoices).order(id: :desc).limit(100)
  end
  def cancel_subscription
    sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    subscription = LightekCommerce::Subscription.for_sites(sites).find(params[:id])
    LightekCommerce::SubscriptionCancellation.schedule!(subscription: subscription)
    redirect_to dashboard_commerce_path(site_id: subscription.order.site_id), notice: "Cancellation scheduled for the end of the paid billing period."
  rescue Stripe::StripeError
    redirect_to dashboard_commerce_path, alert: "Cancellation could not be confirmed. Please retry."
  end
end
