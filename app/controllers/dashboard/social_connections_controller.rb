# frozen_string_literal: true
class Dashboard::SocialConnectionsController < Dashboard::SettingsHomeController
  before_action :set_site
  def index
    @connections = LightekMarketing::SocialConnection.where(site: @site).order(:id)
    @posts = LightekMarketing::SocialPost.joins(:campaign).where(lightek_marketing_campaigns: {site_id: @site.id}).includes(:campaign, :connection).order(created_at: :desc).limit(30)
    @campaigns = LightekMarketing::Campaign.where(site: @site, channel: "social", status: "ready")
  end
  def create
    raise CanCan::AccessDenied unless LightekSettings::WebsiteIdentity.sites_for(current_user).exists?(id: @site.id)
    LightekMarketing::SocialVault.store!(site: @site, provider: params.require(:provider), account: params.require(:account_label), credentials: params.require(:credentials).permit(:page_id, :instagram_user_id, :access_token).to_h, actor: current_user)
    LightekMarketing::SocialConnection.create!(site: @site, provider: params.require(:provider),
      account_label: params.require(:account_label), publish_endpoint: "https://graph.facebook.com",
      credential_key: LightekMarketing::SocialVault.slug(site_id: @site.id, provider: params.require(:provider), account: params.require(:account_label)), enabled: true)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Provider credentials saved in Vault."
  rescue ActiveRecord::RecordInvalid, ArgumentError, KeyError => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  def disable
    raise CanCan::AccessDenied unless LightekSettings::WebsiteIdentity.sites_for(current_user).exists?(id: @site.id)
    connection = LightekMarketing::SocialConnection.where(site: @site).find(params.require(:connection_id))
    LightekVault::Service.disable!(slug: connection.credential_key, requested_by: current_user.email_address)
    connection.update!(enabled: false, disabled_at: Time.current)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Social connection disabled and Vault credentials revoked."
  end
  def retry_publication
    post = LightekMarketing::SocialPost.joins(:campaign).where(lightek_marketing_campaigns: {site_id: @site.id}).find(params.require(:post_id))
    LightekMarketing::SocialPublicationOperations.retry!(post: post)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Publication retried; current provider status recorded."
  rescue LightekMarketing::SocialPublicationOperations::Invalid, LightekMarketing::SocialDispatch::Unavailable, LightekMarketing::SocialProviders::Error, LightekMarketing::TiktokVideoUpload::Invalid => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  def refresh_submission
    post = LightekMarketing::SocialPost.joins(:campaign).where(lightek_marketing_campaigns: {site_id: @site.id}).find(params.require(:post_id))
    LightekMarketing::TiktokSubmissionLifecycle.refresh!(post: post)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "TikTok submission status refreshed."
  rescue LightekMarketing::TiktokVideoUpload::Invalid, ArgumentError => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  def test_connection
    connection = LightekMarketing::SocialConnection.where(site: @site).find(params.require(:connection_id))
    LightekMarketing::MetaConnectionHealth.check!(connection: connection)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "Provider verified connection is active."
  rescue LightekMarketing::MetaConnectionHealth::Unavailable => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  def publish
    connection = LightekMarketing::SocialConnection.where(site: @site).find(params.require(:connection_id))
    campaign = LightekMarketing::Campaign.where(site: @site, channel: "social", status: "ready").find(params.require(:campaign_id))
    post = LightekMarketing::SocialPost.find_or_create_by!(campaign: campaign, connection: connection)
    raise LightekMarketing::SocialDispatch::Unavailable, "Already published" if post.status == "published"
    LightekMarketing::SocialDispatch.call!(post: post)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: (connection.provider == "tiktok" ? "Video submitted to TikTok inbox; publication is not yet confirmed." : "Social publication confirmed.")
  rescue LightekMarketing::SocialDispatch::Unavailable, LightekMarketing::MetaConnectionHealth::Unavailable, LightekMarketing::SocialProviders::Error, LightekMarketing::TiktokVideoUpload::Invalid, LightekVault::Service::AccessDenied => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end
  private
  def set_site
    @site = LightekAgency::Access.sites_for(current_user).find(params.require(:site_id))
  end
end
