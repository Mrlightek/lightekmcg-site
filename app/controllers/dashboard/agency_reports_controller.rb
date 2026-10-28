# frozen_string_literal: true
class Dashboard::AgencyReportsController < Dashboard::SettingsHomeController
  def index
    @sites = LightekAgency::Access.sites_for(current_user).order(:name, :id)
    ids = @sites.select(:id)
    @orders = LightekCommerce::Order.where(site_id: ids).where(status: %w[paid fulfilled partially_refunded refunded])
    @campaigns = LightekMarketing::Campaign.where(site_id: ids)
    @reports = @sites.map do |site|
      sales = @orders.where(site_id: site.id)
      campaigns = @campaigns.where(site_id: site.id)
      {site: site, sales_cents: sales.sum(:total_cents) - sales.sum(:refunded_cents),
       orders: sales.count, campaigns: campaigns.count,
       subscribed: LightekMarketing::Contact.subscribed.where(site_id: site.id).count,
       messages_queued: LightekMarketing::Delivery.joins(:campaign).where(lightek_marketing_campaigns: {site_id: site.id}, status: "queued").count}
    end
  end
end
