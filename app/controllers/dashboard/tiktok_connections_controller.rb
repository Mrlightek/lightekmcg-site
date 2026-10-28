# frozen_string_literal: true
class Dashboard::TiktokConnectionsController < Dashboard::SettingsHomeController
  before_action :require_owned_site!, only: :start

  def start
    state = SecureRandom.urlsafe_base64(32)
    session[:tiktok_oauth] = {state: state, site_id: @site.id, user_id: current_user.id, started_at: Time.current.to_i}
    url = LightekMarketing::TiktokOauth.authorize_url(state: state, redirect_uri: callback_dashboard_tiktok_connection_url)
    redirect_to url, allow_other_host: true
  rescue LightekMarketing::TiktokOauth::Error, LightekVault::Service::AccessDenied => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end

  def callback
    pending = session.delete(:tiktok_oauth).to_h.with_indifferent_access
    raise LightekMarketing::TiktokOauth::Error, "Authorization expired or invalid" if pending.blank? ||
      pending[:user_id].to_i != current_user.id || pending[:started_at].to_i < 10.minutes.ago.to_i ||
      pending[:state].blank? || !ActiveSupport::SecurityUtils.secure_compare(pending[:state], params[:state].to_s)
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(pending[:site_id])
    raise LightekMarketing::TiktokOauth::Error, "TikTok denied authorization" if params[:error].present?
    tokens = LightekMarketing::TiktokOauth.exchange!(code: params.require(:code), redirect_uri: callback_dashboard_tiktok_connection_url)
    LightekMarketing::TiktokOauth.store_tokens!(site: @site, user: current_user, tokens: tokens)
    redirect_to dashboard_social_connections_path(site_id: @site.id), notice: "TikTok connected. Video drafts can now be submitted from Social Publishing."
  rescue LightekMarketing::TiktokOauth::Error, LightekVault::Service::AccessDenied, ActionController::ParameterMissing, ActiveRecord::RecordNotFound => e
    redirect_to dashboard_business_hub_path, alert: e.message
  end

  private

  def require_owned_site!
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end
end
