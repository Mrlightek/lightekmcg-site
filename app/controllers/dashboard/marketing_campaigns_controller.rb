# frozen_string_literal: true
class Dashboard::MarketingCampaignsController < Dashboard::CommerceBaseController
  protect_from_forgery with: :exception
  before_action :set_site
  before_action :set_campaign, only: %i[edit update destroy send_email send_audience schedule studio]
  def studio
    scene = LightekMarketing::StudioProduction.open!(campaign: @campaign, actor: current_user)
    path = if scene.settings["editor_kind"] == "video"
      dashboard_studio_editor_path(kind: "video", id: scene.id, site_id: @site.id)
    else
      dashboard_production_workspace_path(site_id: @site.id, scene_id: scene.id, workspace: "script")
    end
    redirect_to path, status: :see_other
  rescue LightekPwa::Policy::Denied, ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to edit_dashboard_marketing_campaign_path(@campaign, site_id: @site.id), alert: error.message, status: :see_other
  end
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
  def schedule
    raise ArgumentError, "Only ready email campaigns can be scheduled" unless @campaign.channel == "email" && @campaign.status == "ready"
    raise ArgumentError, "Choose a future start time" unless @campaign.starts_at&.future?
    LightekMarketing::ScheduledCampaignJob.set(wait_until: @campaign.starts_at).perform_later(@campaign.id)
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Email audience campaign scheduled."
  rescue ArgumentError => e
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), alert: e.message
  end
  def send_audience
    LightekMarketing::AudienceDispatch.call!(campaign: @campaign)
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Subscribed audience queued in Lightek Mail."
  rescue ArgumentError => e
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), alert: e.message
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
    @site = LightekAgency::Access.sites_for(current_user).find(params.require(:site_id))
  end
  def set_campaign
    @campaign = LightekMarketing::Campaign.where(site: @site).find(params[:id])
  end
  def campaign_params
    params.require(:campaign).permit(:name, :channel, :status, :headline, :message, :cta_label, :cta_url, :starts_at, :ends_at, :mail_account_id, :recipient_email, :media_url)
  end
end
