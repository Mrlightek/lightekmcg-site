class Dashboard::CampaignContentController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_workbench
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError do |error|
    redirect_to dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), alert: error.is_a?(ActiveRecord::StaleObjectError) ? 'This draft changed. Reopen it before reviewing.' : error.message, status: :see_other
  end
  def index
    @sender_address = LightekMail::Account.where(id: @campaign.mail_account_id, user_id: [current_user.id, @site.tenant_id]).pick(:address) if @campaign.has_attribute?(:mail_account_id)
    @variants = LightekMarketing::ContentVariant.where(site: @site, campaign: @campaign).includes(:approved_by).order(created_at: :desc, id: :desc).limit(30)
    @links = LightekGrowth::Link.where(site: @site, campaign: @campaign, enabled: true).order(:label)
  end
  def generate
    @workbench.generate!(campaign_id: @campaign.id, request_key: params[:request_key], tracking_link_id: params[:tracking_link_id].presence)
    redirect_to dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), notice: 'Three editable variations prepared using the reviewed business brief.', status: :see_other
  end
  def update
    variant = @campaign.content_variants.where(site: @site).find(params[:id])
    @workbench.update!(id: variant.id, version: params[:lock_version], values: params.require(:variant).permit(*LightekMarketing::ContentVariant::COPY_FIELDS))
    redirect_to dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), notice: 'Draft revision saved. Review this version before approval.', status: :see_other
  end
  def approve
    raise ArgumentError, 'Confirm you reviewed this exact draft.' unless params[:confirmed] == '1'
    variant = @campaign.content_variants.where(site: @site).find(params[:id])
    @workbench.approve!(id: variant.id, version: params[:lock_version])
    redirect_to dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), notice: 'Reviewed copy applied to the campaign. Publishing and audience sends remain separate actions.', status: :see_other
  end
  private
  def set_workbench
    @site = LightekSales::Access.sites_for(current_user).find(params.require(:site_id))
    @campaign = LightekMarketing::Campaign.where(site: @site).find(params.require(:campaign_id))
    @workbench = LightekMarketing::ContentWorkbench.new(actor: current_user, site: @site)
  end
end
