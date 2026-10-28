# frozen_string_literal: true
class Dashboard::MetaConnectionsController < Dashboard::SettingsHomeController
  before_action :require_site_owner!, only: :start

  def start
    state = SecureRandom.urlsafe_base64(32)
    session[:meta_oauth] = {state: state, site_id: @site.id, user_id: current_user.id, started_at: Time.current.to_i}
    url = LightekMarketing::MetaOauth.authorization_url(state: state, redirect_uri: callback_dashboard_meta_connection_url)
    redirect_to url, allow_other_host: true
  rescue LightekMarketing::MetaOauth::Error, LightekVault::Service::AccessDenied => e
    redirect_to dashboard_social_connections_path(site_id: @site.id), alert: e.message
  end

  def callback
    pending = session.delete(:meta_oauth).to_h.with_indifferent_access
    raise LightekMarketing::MetaOauth::Error, "Authorization expired or invalid" if pending.blank? ||
      pending[:user_id].to_i != current_user.id || pending[:started_at].to_i < 10.minutes.ago.to_i ||
      pending[:state].blank? || !ActiveSupport::SecurityUtils.secure_compare(pending[:state], params[:state].to_s)
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(pending[:site_id])
    raise LightekMarketing::MetaOauth::Error, "Meta authorization declined" if params[:error].present?
    token = LightekMarketing::MetaOauth.exchange!(code: params.require(:code), redirect_uri: callback_dashboard_meta_connection_url)
    pages = LightekMarketing::MetaOauth.pages!(user_token: token)
    raise LightekMarketing::MetaOauth::Error, "No authorized Facebook Pages found" if pages.empty?
    LightekMarketing::MetaOauth.store_pages!(site: site, actor: current_user, pages: pages)
    redirect_to dashboard_social_connections_path(site_id: site.id), notice: "Connected #{pages.length} Facebook Page(s) and available Instagram professional accounts."
  rescue LightekMarketing::MetaOauth::Error, LightekVault::Service::AccessDenied, ActionController::ParameterMissing, ActiveRecord::RecordNotFound => e
    redirect_to dashboard_business_hub_path, alert: e.message
  end

  private

  def require_site_owner!
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end
end
