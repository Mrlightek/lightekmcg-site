class Dashboard::GrowthController < Dashboard::SettingsHomeController
  protect_from_forgery with: :exception
  skip_before_action :require_settings_operator!
  before_action :set_growth
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
  private
  def set_growth
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
    @growth = LightekGrowth::Workspace.new(actor: current_user, site: @site)
  end
end
