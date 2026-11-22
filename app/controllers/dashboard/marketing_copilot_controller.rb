class Dashboard::MarketingCopilotController < Dashboard::SettingsHomeController
  protect_from_forgery with: :exception
  skip_before_action :require_settings_operator!
  before_action :set_copilot
  rescue_from LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: params[:id]), alert: error.message, status: :see_other
  end
  def index
    @brief = LightekGrowth::Brief.find_or_initialize_by(site: @site)
    @kits = LightekGrowth::MarketingKit.where(site: @site).order(id: :desc).limit(20)
    @kit = params[:kit_id].present? ? LightekGrowth::MarketingKit.where(site: @site).find(params[:kit_id]) : @kits.first
    if @kit
      @current = @copilot.current?(@kit)
      @check_ins = @kit.check_ins.includes(:actor).index_by(&:day_index)
      @variants = LightekMarketing::ContentVariant.where(site: @site, campaign_id: @kit.campaign_id, id: @kit.snapshot['variant_ids']).order(:id)
      @link = LightekGrowth::Link.where(site: @site, campaign_id: @kit.campaign_id).find_by(id: @kit.snapshot['link_id'])
      @follow_up_leads = LightekSales::Lead.where(site: @site, id: @kit.snapshot['follow_ups'].map { |row| row['lead_id'] }).index_by(&:id)
      @showcase = LightekGrowth::FeatureShowcase.where(site: @site, marketing_kit: @kit).includes(clips: {file_attachment: :blob}).first
      if @showcase && (link_id = @showcase.snapshot['demo_promotion_link_id'])
        @demo_link = LightekGrowth::Link.where(site: @site, campaign: @kit.campaign).find_by(id: link_id)
        @demo_funnel = LightekGrowth::DemoShowcase.funnel(@site, @kit.campaign_id)
        @demo_variants = LightekMarketing::ContentVariant.where(campaign: @kit.campaign, batch_key: "demo-walkthrough-#{@showcase.id}").order(:id)
      end
      @execution = LightekGrowth::MarketingExecution.find_by(marketing_kit: @kit)
    end
  end
  def create
    kit = @copilot.prepare!(values: params.require(:kit).permit(:minutes_per_day, :source, :destination_path, :cta_label).to_h, request_key: params[:request_key])
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: kit.id), notice: 'Your marketing kit is ready. Review the copy and work through one day at a time.', status: :see_other
  end
  def check_in
    @copilot.check_in!(id: params[:id], day_index: params[:day_index], status: params[:status], note: params[:note])
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: params[:id], anchor: "kit-day-#{params[:day_index]}"), notice: 'Your check-in was recorded. Campaign and sales receipts remain separate evidence.', status: :see_other
  end
  def follow_up
    task = @copilot.follow_up_task!(id: params[:id], lead_id: params[:lead_id])
    redirect_to dashboard_sales_path(site_id: @site.id, tab: 'tasks'), notice: "Follow-up task ##{task.id} is ready. No message was sent.", status: :see_other
  end
  def execute
    raise ArgumentError, 'Confirm the work to execute' unless params[:confirmed] == '1'
    goal = LightekGrowth::MarketingExecutionPlan.new(actor: current_user, site: @site).start!(kit_id: params[:id])
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: params[:id]), notice: "Execution goal ##{goal.id} #{goal.status}. Page/video production and follow-up preparation are tracked separately from publishing or sending.", status: :see_other
  end
  def video
    showcase = LightekGrowth::FeatureShowcase.where(site: @site).find(params[:id])
    clip = showcase.clips.find_by!(position: params[:position])
    raise ActiveRecord::RecordNotFound unless clip.ready?
    response.set_header('Cache-Control', 'private, no-store')
    send_data clip.file.download, type: 'video/mp4', disposition: 'inline', filename: "#{clip.feature_key}-overview.mp4"
  end
  def screenshot
    showcase = LightekGrowth::FeatureShowcase.where(site: @site).find(params[:id])
    clip = showcase.clips.find_by!(position: params[:position])
    LightekBlog::Images.deliver(self, LightekGrowth::DemoShowcase.image!(clip, params[:attachment_id]))
  end

  def save_screenshot
    change_screenshot { |clip| LightekGrowth::DemoShowcase.add_capture!(clip, params[:screenshot], params[:caption]) }
  end

  def remove_screenshot
    change_screenshot { |clip| clip.screenshots_attachments.find(params[:attachment_id]).purge_later }
  end

  def prepare_demo_promotion
    showcase = LightekGrowth::FeatureShowcase.where(site: @site).find(params[:id])
    link = LightekGrowth::Link.where(site: @site, campaign: showcase.marketing_kit.campaign)
      .find(showcase.snapshot.fetch('demo_promotion_link_id'))
    unless LightekGrowth::DemoShowcase.promotion_ready?(showcase, link)
      raise ArgumentError, 'Publish the approved walkthrough and enable public demo requests before preparing promotion.'
    end

    LightekMarketing::ContentWorkbench.new(actor: current_user, site: @site).generate!(campaign_id: link.campaign_id,
      request_key: "demo-walkthrough-#{showcase.id}", tracking_link_id: link.id, purpose: 'marketing_kit')
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase.marketing_kit_id),
      notice: 'Promotion copy is ready in Content review.', status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase&.marketing_kit_id), alert: error.message, status: :see_other
  end

  def approve_showcase
    raise ArgumentError, 'Confirm review of the feature claims, videos and screenshots' unless params[:confirmed] == '1'
    showcase = LightekGrowth::ShowcaseBuilder.new(actor: current_user, site: @site).approve!(id: params[:id])
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase.marketing_kit_id), notice: 'Walkthrough media approved for this page. Publish the reviewed draft through the normal website editor when ready.', status: :see_other
  end
  private
  def change_screenshot
    showcase = LightekGrowth::FeatureShowcase.where(site: @site).find(params[:id])
    showcase.with_lock do
      LightekGrowth::ShowcaseBuilder.new(actor: current_user, site: @site).authorize!
      raise ArgumentError, 'Wait for the walkthrough draft to finish, then manage screenshots before approval.' unless showcase.status == 'completed' && !showcase.approved_at

      yield showcase.clips.find_by!(position: params[:position])
    end
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase.marketing_kit_id), notice: 'Walkthrough screenshots updated.', status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_marketing_copilot_path(site_id: @site.id, kit_id: showcase&.marketing_kit_id), alert: error.message, status: :see_other
  end

  def set_copilot
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
    @copilot = LightekGrowth::MarketingCopilot.new(actor: current_user, site: @site)
  end
end
