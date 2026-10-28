# frozen_string_literal: true
class Dashboard::SocialConnectionsController < Dashboard::SettingsHomeController
  before_action :set_site
  def index
    @connections = LightekMarketing::SocialConnection.where(site: @site).order(:id)
    @campaigns = LightekMarketing::Campaign.where(site: @site, channel: "social", status: "ready")
  end
  def create
    LightekMarketing::SocialConnection.create!(site: @site, provider: "webhook",
      account_label: params.require(:account_label), publish_endpoint: "https://gateway.local.invalid",
      credential_key: "operator_gateway", enabled: true)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Gateway publishing destination recorded."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  def publish
    connection = LightekMarketing::SocialConnection.where(site: @site).find(params.require(:connection_id))
    campaign = LightekMarketing::Campaign.where(site: @site, channel: "social", status: "ready").find(params.require(:campaign_id))
    post = LightekMarketing::SocialPost.find_or_create_by!(campaign: campaign, connection: connection)
    LightekMarketing::SocialDispatch.call!(post: post)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Social publication confirmed."
  rescue LightekMarketing::SocialDispatch::Unavailable => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  private
  def set_site
    @site = LightekAgency::Access.sites_for(current_user).find(params.require(:site_id))
  end
end
