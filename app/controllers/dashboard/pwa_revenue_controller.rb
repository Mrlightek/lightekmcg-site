class Dashboard::PwaRevenueController < DymondDash::ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  before_action :context
  protect_from_forgery with: :exception
  before_action { response.set_header('Cache-Control', 'private, no-store') }
  rescue_from LightekPwa::Policy::Denied do |e|
    render plain: e.message, status: :forbidden
  end
  rescue_from ArgumentError, LightekPwa::Plans::Unavailable, ActiveRecord::RecordInvalid do |e|
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), alert: e.message
  end
  def show
    @launch_readiness = LightekPwa::LaunchReadiness.report(site: @site)
    @youtube_uploads = LightekPwa::YoutubeUpload.where(site: @site).order(id: :desc).limit(30)
    @creator_earnings = LightekPwa::CreatorEarning.joins(:creator_payment).where(lightek_pwa_creator_payments: {site_id: @site.id}).order(id: :desc).limit(30)
    @packages = LightekCommerce::Product.visible.where(site: @site, product_type: 'lightek_instance', billing_interval: 'month').joins(:hosting_package).where(hosting_packages: {active: true})
    @learning_build = NevaehManualBuild.where(creator: current_user).where('name LIKE ?', 'PWA business model · %').order(id: :desc).first
    @learning_models = NevaehLanguageModel.where(enabled: true, visibility: 'internal').order(:name).limit(50)
    @learning_plan = @learning_build && NevaehLearningPlan.where(nevaeh_manual_build: @learning_build, actor: current_user).order(id: :desc).first
    @membership = LightekPwa::Plans.payload(user: current_user, site: @site)
    @receipts = LightekPwa::YoutubeRevenue.where(site: @site).order(id: :desc).limit(100)
    @purchases = LightekPwa::Purchase.where(site: @site).includes(:user, order: :commerce_subscription).order(id: :desc).limit(100)
  end
  def enable
    raise ArgumentError, 'Confirm payment configuration and ability to deliver the listed service bundles' unless params[:ready] == '1'
    raise ArgumentError, 'Configure payments before opening paid membership' if DymondBank::StripeCredentials.secret_key.blank?
    LightekPwa::Plans.install!(site: @site, actor: current_user, personal_product_id: params[:personal_product_id], business_product_id: params[:business_product_id])
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Paid membership is open. New members can purchase in the PWA.'
  end
  def prepare_nevaeh
    build = NevaehIntelligences::PwaLearning.prepare!(actor: current_user)
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "PWA source build ##{build.id} prepared. Review the source batches before training."
  end
  def train_nevaeh
    raise ArgumentError, 'Review the installed PWA guide, audit and source batches before training' unless params[:reviewed] == '1'
    build = NevaehManualBuild.where(creator: current_user).find(params.require(:build_id))
    model = NevaehLanguageModel.where(enabled: true, visibility: 'internal').find(params.require(:model_id))
    plan = NevaehIntelligences::PwaLearning.train!(build: build, model: model, actor: current_user, epochs: params.require(:epochs))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "Learning plan ##{plan.id}: #{plan.status}. Inspect actual checkpoint acceptance before claiming completed training."
  end
  def disable
    @site.with_lock do
      configuration = @site.manifest.to_h.fetch('pwa_commerce', {}).merge('enabled' => false)
      @site.update!(manifest: @site.manifest.to_h.merge('pwa_commerce' => configuration))
    end
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'New paid memberships are paused. Existing paid periods are preserved.'
  end
  def import
    entries = LightekPwa::YoutubeImport.call(site: @site, actor: current_user, file: params[:report], source_reference: params[:source_reference])
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "#{entries.size} revenue estimates recorded. No payout or bank balance was created."
  end
  private
  def context
    raise LightekPwa::Policy::Denied, 'Platform owner access required' unless current_user&.role == 'super_admin'
    @site = DymondSite::Site.where(tenant: current_user).find(params.require(:site_id))
  end
end
