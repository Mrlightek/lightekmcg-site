# frozen_string_literal: true
class Dashboard::MarketingContactsController < Dashboard::SettingsHomeController
  before_action :set_site
  def index
    @contacts = LightekMarketing::Contact.where(site: @site).order(created_at: :desc).limit(300)
  end
  def create
    # Admin entry is not itself proof of marketing consent.
    LightekMarketing::Contact.find_or_create_by!(site: @site, email: params.require(:email))
    redirect_to dashboard_marketing_contacts_path(site_id: @site.id), notice: "Contact saved. Explicit subscription required before campaigns."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_marketing_contacts_path(site_id: @site.id), alert: e.message
  end
  private
  def set_site
    @site = LightekAgency::Access.sites_for(current_user).find(params.require(:site_id))
  end
end
