# frozen_string_literal: true
class Dashboard::MarketingCampaignsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_site
  before_action :set_campaign, only: %i[edit update destroy send_email send_audience schedule studio sync_studio_brief]
  rescue_from ActiveRecord::StaleObjectError do
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), alert: 'Campaign changed. Reopen it before saving.'
  end
  def studio
    scene = LightekMarketing::StudioProduction.open!(campaign: @campaign, actor: current_user)
    path = if scene.settings["editor_kind"] == "video"
      dashboard_studio_editor_path(kind: "video", id: scene.id, site_id: @site.id)
    else
      dashboard_production_workspace_path(site_id: @site.id, scene_id: scene.id, workspace: "script")
    end
    changed = scene.settings['campaign_content_digest'].present? && scene.settings['campaign_content_digest'] != @campaign.content_digest
    redirect_to path, notice: changed ? 'Production reopened. The campaign copy changed; your Studio edits were preserved. Replace the script explicitly from the campaign editor if needed.' : 'Campaign production ready.', status: :see_other
  rescue LightekPwa::Policy::Denied, ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to edit_dashboard_marketing_campaign_path(@campaign, site_id: @site.id), alert: error.message, status: :see_other
  end
  def sync_studio_brief
    raise ArgumentError, 'Confirm replacing the existing Studio script.' unless params[:confirmed] == '1'
    LightekMarketing::StudioProduction.sync_brief!(campaign: @campaign, actor: current_user)
    redirect_to edit_dashboard_marketing_campaign_path(@campaign, site_id: @site.id), notice: 'Current campaign copy replaced the Studio script. Timeline and media edits were preserved.', status: :see_other
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
    if @campaign.has_attribute?(:lock_version) && (!params.dig(:campaign, :lock_version).to_s.match?(/\A\d+\z/) || params.dig(:campaign, :lock_version).to_i != @campaign.lock_version)
      raise ActiveRecord::StaleObjectError.new(@campaign, 'update')
    end
    return redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), notice: "Campaign updated." if @campaign.update(campaign_params)
    render :edit, status: :unprocessable_entity
  end
  def schedule
    raise ArgumentError, "Only ready email campaigns can be scheduled" unless @campaign.channel == "email" && @campaign.status == "ready"
    raise ArgumentError, "Choose a future start time" unless @campaign.starts_at&.future?
    LightekMarketing::ScheduledCampaignJob.set(wait_until: @campaign.starts_at).perform_later(@campaign.id, @campaign.content_digest)
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
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to dashboard_marketing_campaigns_path(site_id: @site.id), alert: "This campaign has retained tracking or content history. Mark it completed and disable any links to preserve results."
  end
  private
  def set_site
    @site = LightekSales::Access.sites_for(current_user).find(params.require(:site_id))
  end
  def set_campaign
    @campaign = LightekMarketing::Campaign.where(site: @site).find(params[:id])
  end
  def campaign_params
    params.require(:campaign).permit(:name, :production_format, :channel, :status, :headline, :message, :cta_label, :cta_url, :starts_at, :ends_at, :mail_account_id, :recipient_email, :media_url)
  end
end
