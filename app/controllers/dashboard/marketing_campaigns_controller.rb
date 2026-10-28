# frozen_string_literal: true
class Dashboard::MarketingCampaignsController < Dashboard::SettingsHomeController
  before_action :set_site
  before_action :set_campaign, only: %i[edit update destroy send_email send_audience]
  def index
    @campaigns = LightekMarketing::Campaign.where(site: @site).order(updated_at: :desc)
  end
  def new
    @campaign = LightekMarketing::Campaign.new(site: @site)
  end
  def create
    @campaign = LightekMarketing::Campaign.new(campaign_params.merge(site: @site))
    return redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Campaign saved." if @campaign.save
    render :new, status: :unprocessable_entity
  end
  def edit; end
  def update
    return redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Campaign updated." if @campaign.update(campaign_params)
    render :edit, status: :unprocessable_entity
  end
  def send_email
    LightekMarketing::EmailDelivery.call!(campaign: @campaign, actor: current_user)
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Campaign handed to Lightek Mail."
  rescue LightekMarketing::EmailDelivery::Invalid, LightekMail::Submission::Unavailable, ArgumentError => e
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), alert: e.message
  end
  def destroy
    @campaign.destroy!
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Campaign deleted."
  end
  private
  def set_site
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params.require(:site_id))
  end
  def set_campaign
    @campaign = LightekMarketing::Campaign.where(site: @site).find(params[:id])
  end
  def campaign_params
    params.require(:campaign).permit(:name, :channel, :status, :headline, :message, :cta_label, :cta_url, :starts_at, :ends_at, :mail_account_id, :recipient_email)
  end
end
