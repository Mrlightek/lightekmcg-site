class Dashboard::CampaignPerformanceController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_performance
  rescue_from ActiveRecord::RecordInvalid, ArgumentError do |error|
    redirect_to dashboard_campaign_performance_path(site_id: @site.id), alert: error.message, status: :see_other
  end
  def index
    @comparisons = LightekGrowth::Comparison.where(site: @site).order(id: :desc).limit(30)
    @comparison = params[:comparison_id].present? ? LightekGrowth::Comparison.where(site: @site).find(params[:comparison_id]) : @comparisons.first
    @campaigns = LightekMarketing::Campaign.where(site: @site, channel: 'social').order(:name).limit(200)
    @reviews = @comparison ? @comparison.reviews.order(id: :desc).limit(10) : []
    raise ActiveRecord::RecordNotFound if params[:review_id].present? && !@comparison
    @review = params[:review_id].present? ? @comparison.reviews.find(params[:review_id]) : @reviews.first
    @arms = @comparison ? @comparison.arms.includes(:campaign, :link).order(:id) : []
  end
  def create
    comparison = @performance.create!(values: params.require(:comparison).permit(:name, :hypothesis, :variable, :starts_on, :ends_on, :control_campaign_id, :challenger_campaign_id, :source, :medium, :control_path, :challenger_path, :confirmed), request_key: params[:request_key])
    redirect_to dashboard_campaign_performance_path(site_id: @site.id, comparison_id: comparison.id), notice: 'Versions and placement links pinned. Review and use the assigned links; no campaign was published.', status: :see_other
  end
  def review
    review = @performance.review!(comparison_id: params[:id], request_key: params[:request_key])
    redirect_to @performance.receipt(review).fetch('url'), notice: 'Measured review saved. Read the coverage and limitations with the result.', status: :see_other
  end
  def draft
    raise ArgumentError, 'Confirm the reviewed starting point before preparing a draft.' unless params[:confirmed] == '1'
    receipt = @performance.followup!(review_id: params[:id])
    redirect_to edit_dashboard_marketing_campaign_path(receipt.campaign_id, site_id: @site.id), notice: 'Editable starting copy prepared. Make the deliberate change, then use content review and Studio. Nothing was approved or published.', status: :see_other
  end
  private
  def set_performance
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = @sites.find(params.require(:site_id))
    @performance = LightekGrowth::Performance::Workspace.new(actor: current_user, site: @site)
  end
end
