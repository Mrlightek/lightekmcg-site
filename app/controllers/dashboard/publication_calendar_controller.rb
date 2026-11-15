class Dashboard::PublicationCalendarController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_calendar
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError do |error|
    redirect_to dashboard_publication_calendar_path(site_id: @site.id), alert: error.is_a?(ActiveRecord::StaleObjectError) ? 'This slot changed. Reopen the calendar.' : error.message, status: :see_other
  end
  def index
    @from = Date.iso8601(params[:from].presence || Date.current.iso8601)
    @through = @from + 30
    @slots = LightekMarketing::PublicationSlot.where(site: @site, scheduled_at: @from.beginning_of_day..@through.end_of_day).includes(:campaign, :connection, :scheduled_by, :social_post).order(:scheduled_at).limit(200)
    @campaigns = LightekMarketing::Campaign.where(site: @site, channel: 'social', status: 'ready', content_review_required: true).order(:name)
    @connections = LightekMarketing::SocialConnection.where(site: @site, enabled: true, provider: %w[facebook instagram tiktok]).order(:account_label)
    @campaign = params[:campaign_id].present? ? LightekMarketing::Campaign.where(site: @site, channel: 'social').find(params[:campaign_id]) : LightekMarketing::Campaign.where(site: @site, channel: 'social').order(updated_at: :desc).first
    @media_locked = @campaign && (LightekMarketing::SocialPost.where(campaign: @campaign).exists? || LightekMarketing::Delivery.where(campaign: @campaign).exists?)
    @media = @campaign ? LightekMarketing::MediaBinding.where(site: @site, campaign: @campaign).order(id: :desc).limit(20) : []
    @artifacts = @campaign && !@media_locked ? LightekMarketing::CampaignMedia.new(actor: current_user, site: @site).artifacts.to_a.select { |a| a.file.attached? && !a.studio_operation.metadata['draft_preview'] && LightekMarketing::CampaignMedia::TYPES.key?(a.file.blob.content_type) && a.file.blob.byte_size.between?(1, 1.gigabyte) } : []
    @operator = current_user.role.in?(%w[admin super_admin])
  rescue Date::Error
    redirect_to dashboard_publication_calendar_path(site_id: @site.id), alert: 'Choose a valid starting date.', status: :see_other
  end
  def create
    time = LightekMarketing::PublicationCalendar.parse_local(value: params[:scheduled_local], zone: params[:time_zone])
    slot = @calendar.schedule!(campaign_id: params[:campaign_id], connection_id: params[:connection_id], scheduled_at: time, time_zone: params[:time_zone], request_key: params[:request_key])
    redirect_to dashboard_publication_calendar_path(site_id: @site.id), notice: "Calendar request: #{slot.status.humanize}. Provider confirmation is recorded separately.", status: :see_other
  end
  def cancel
    @calendar.cancel!(id: params[:id], version: params[:lock_version])
    redirect_to dashboard_publication_calendar_path(site_id: @site.id), notice: 'Calendar slot canceled. No provider request was canceled by this action.', status: :see_other
  end
  def attach_media
    LightekMarketing::CampaignMedia.new(actor: current_user, site: @site).attach!(campaign_id: params[:campaign_id], artifact_id: params[:artifact_id], delivery_host: request.host)
    redirect_to dashboard_campaign_content_path(site_id: @site.id, campaign_id: params[:campaign_id]), notice: 'Finished export attached. Review and approve the final campaign payload before scheduling.', status: :see_other
  end
  def revoke_media
    LightekMarketing::CampaignMedia.new(actor: current_user, site: @site).revoke!(id: params[:id])
    redirect_to dashboard_publication_calendar_path(site_id: @site.id), notice: 'The media entry link is revoked. Existing storage URLs and downloaded copies may remain usable.', status: :see_other
  end
  private
  def set_calendar
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = @sites.find(params.require(:site_id))
    LightekGrowth::Workspace.new(actor: current_user, site: @site).revalidate!
    @calendar = LightekMarketing::PublicationCalendar.new(actor: current_user, site: @site)
  end
end
