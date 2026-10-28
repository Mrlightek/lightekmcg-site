# frozen_string_literal: true
class Dashboard::CommerceOrdersController < Dashboard::SettingsHomeController
  def index
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
    @orders = LightekCommerce::Order.where(site: @site).includes(:items).order(created_at: :desc).limit(150)
  end
end
