class Dashboard::GrowthController < Dashboard::SettingsHomeController
  protect_from_forgery with: :exception
  skip_before_action :require_settings_operator!
  before_action :set_growth
  helper_method :growth_step_path
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, ActiveRecord::StaleObjectError do |error|
    redirect_to dashboard_growth_path(site_id: @site.id), alert: error.is_a?(ActiveRecord::StaleObjectError) ? 'The brief changed. Reopen it before saving.' : error.message, status: :see_other
  end
  def index
    @brief = LightekGrowth::Brief.find_or_initialize_by(site: @site)
    @campaigns = LightekMarketing::Campaign.where(site: @site).order(:name)
    @links = LightekGrowth::Link.where(site: @site).includes(:campaign).order(created_at: :desc).limit(100)
    @funnel = LightekGrowth::Funnel.new(site: @site, from: params[:from].presence || 29.days.ago.to_date, to: params[:to].presence || Date.current)
    @stages, @money, @unknown = @funnel.stages, @funnel.money, @funnel.unknown
    @recent_orders = @funnel.orders.includes(growth_visit: {link: :campaign}).order(id: :desc).limit(20)
    @tab = 'growth'
    plans = LightekGrowth::Plan.where(site: @site).order(plan_on: :desc, revision: :desc)
    @plan = params[:plan_id].present? ? plans.find(params[:plan_id]) : plans.where(plan_on: Date.current).first
    @plan_steps = @plan ? @plan.steps.includes(:resolved_by).to_a : []
    @plan_current = @plan&.current?
    @plan_history = plans.limit(7)
  rescue ArgumentError
    redirect_to dashboard_growth_path(site_id: @site.id), alert: 'Choose valid ISO dates and a range of up to 366 days.', status: :see_other
  end
  def brief
    @growth.save_brief!(values: params.require(:brief).permit(*LightekGrowth::Brief::FIELDS), version: params[:brief][:lock_version])
    redirect_to dashboard_growth_path(site_id: @site.id), notice: 'Growth brief saved.', status: :see_other
  end
  def create_link
    @growth.create_link!(values: params.require(:link).permit(:campaign_id, :label, :source, :medium, :destination_path))
    redirect_to dashboard_growth_path(site_id: @site.id), notice: 'Tracking link created. Use it on the channel you selected.', status: :see_other
  end
  def toggle
    raise ArgumentError, 'Choose enabled or disabled.' unless params[:enabled].in?(%w[0 1])
    @growth.set_enabled!(id: params[:id], enabled: params[:enabled] == '1')
    redirect_to dashboard_growth_path(site_id: @site.id), notice: 'Link availability updated. Historical attribution is retained.', status: :see_other
  end
  def prepare_plan
    plan = planner.prepare!(refresh_from: params[:refresh_from].presence, request_key: params[:request_key])
    redirect_to dashboard_growth_path(site_id: @site.id, plan_id: plan.id, anchor: 'daily-growth-plan'), notice: 'Daily growth plan is ready.', status: :see_other
  end
  def resolve_step
    planner.resolve!(plan_id: params[:plan_id], step_id: params[:id], version: params[:lock_version], status: params[:status], note: params[:note])
    redirect_to dashboard_growth_path(site_id: @site.id, plan_id: params[:plan_id], anchor: 'daily-growth-plan'), notice: 'Your resolution was recorded. Business outcomes remain independently measured.', status: :see_other
  end
  def draft_step
    step = planner.draft_campaign!(plan_id: params[:plan_id], step_id: params[:id], version: params[:lock_version])
    redirect_to edit_dashboard_marketing_campaign_path(step.result.fetch('campaign_id'), site_id: @site.id), notice: 'Editable campaign draft prepared. Review before publishing.', status: :see_other
  end
  private
  def planner = LightekGrowth::DailyPlanner.new(actor: current_user, site: @site)
  def growth_step_path(step)
    if step.result['campaign_id'] && LightekMarketing::Campaign.where(site: @site, id: step.result['campaign_id']).exists?
      return edit_dashboard_marketing_campaign_path(step.result['campaign_id'], site_id: @site.id)
    end
    case step.definition.fetch('destination')
    when 'brief' then dashboard_growth_path(site_id: @site.id, anchor: 'business-brief')
    when 'links' then dashboard_growth_path(site_id: @site.id, anchor: 'campaign-links')
    when 'intake' then dashboard_sales_intake_path(site_id: @site.id)
    when 'tasks' then dashboard_sales_path(site_id: @site.id, tab: 'tasks')
    when 'sales' then dashboard_sales_path(site_id: @site.id, tab: 'pipeline')
    when 'orders' then dashboard_commerce_orders_path(site_id: @site.id)
    when 'campaigns' then dashboard_marketing_campaigns_path(site_id: @site.id)
    when 'performance' then dashboard_campaign_performance_path(site_id: @site.id)
    when 'website_audit' then dashboard_website_audits_path(site_id: @site.id)
    when 'search_growth' then dashboard_search_growth_path(site_id: @site.id)
    when 'website' then dashboard_website_designs_path(site_id: @site.id)
    else raise ArgumentError, 'Unknown growth destination'
    end
  end
  def set_growth
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
    @growth = LightekGrowth::Workspace.new(actor: current_user, site: @site)
  end
end
