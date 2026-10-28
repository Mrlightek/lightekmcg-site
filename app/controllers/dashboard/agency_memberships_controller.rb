# frozen_string_literal: true
class Dashboard::AgencyMembershipsController < Dashboard::SettingsHomeController
  before_action :set_site
  def index
    @memberships = LightekAgency::SiteMembership.where(site: @site).includes(:user)
  end
  def create
    user = User.find_by!(email_address: params.require(:email_address).to_s.strip.downcase)
    LightekAgency::SiteMembership.create!(site: @site, user: user, role: params.require(:role), granted_by: current_user)
    redirect_to dashboard_agency_memberships_path(site_id: @site.id), notice: "Access granted."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_agency_memberships_path(site_id: @site.id), alert: e.message
  end
  def destroy
    LightekAgency::SiteMembership.where(site: @site).find(params[:id]).destroy!
    redirect_to dashboard_agency_memberships_path(site_id: @site.id), notice: "Access revoked."
  end
  private
  def set_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end
end
