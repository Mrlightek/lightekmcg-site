# frozen_string_literal: true
class Dashboard::BusinessHubController < Dashboard::SettingsHomeController
  def index
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name, :id)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first
    return unless @site

    products = LightekCommerce::Product.where(site: @site)
    orders = LightekCommerce::Order.where(site: @site)
    campaigns = LightekMarketing::Campaign.where(site: @site)
    @metrics = {
      products: products.count,
      published_products: products.where(published: true).count,
      low_stock_products: products.where(inventory_quantity: 0..5).count,
      orders: orders.count,
      pending_orders: orders.where(status: "pending_payment").count,
      paid_orders: orders.where(status: %w[paid fulfilled partially_refunded]).count,
      gross_sales_cents: orders.where(status: %w[paid fulfilled partially_refunded refunded]).sum(:total_cents),
      refunded_cents: orders.sum(:refunded_cents),
      campaigns: campaigns.count,
      ready_campaigns: campaigns.where(status: "ready").count,
      sent_campaigns: campaigns.where.not(sent_at: nil).count
    }
    @recent_orders = orders.includes(:items).order(created_at: :desc).limit(8)
    @recent_campaigns = campaigns.order(updated_at: :desc).limit(8)
    @industry_starters = LightekCommerce::IndustryStarters::INDUSTRIES
  end
end
