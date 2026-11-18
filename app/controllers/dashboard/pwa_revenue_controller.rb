class Dashboard::PwaRevenueController < DymondDash::ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  before_action :context
  protect_from_forgery with: :exception
  before_action { response.set_header('Cache-Control', 'private, no-store') }
  rescue_from LightekPwa::Policy::Denied do |e|
    render plain: e.message, status: :forbidden
  end
  rescue_from ArgumentError, LightekPwa::Plans::Unavailable, LightekPwa::MemberBackends::Unavailable, LightekPwa::BackendMigration::Unavailable, LightekPwa::ViewSettlement::Unavailable, ActiveRecord::RecordInvalid do |e|
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), alert: e.message
  end
  def show
    @launch_settings = LightekPwa::LaunchSettings.snapshot
    @youtube_credentials = LightekVault::Secret.active.order(:name).select do |secret|
      secret.usable? && LightekVault::Policy.authorize(secret: secret, consumer: LightekPwa::YoutubeApi::CONSUMER, purpose: 'youtube_publishing').allowed
    end
    @youtube_verification = LightekPwa::LaunchSettings.find_by(id: 1)&.settings.to_h.fetch('youtube_verification', {})
    @starter_region = params[:region].presence || ENV['LIGHTEK_AUTO_VPS_REGION'].presence || 'us-mia'
    begin
      @starter_offer = LightekPwa::MemberBackends.smallest_offer!(actor: current_user, region: @starter_region)
    rescue StandardError => error
      Rails.logger.warn("[PWA] Shared-host quote unavailable: #{error.class}")
      @starter_error = 'The provider quote is unavailable. Refresh after checking the provider connection.'
    end
    @view_batches = LightekPwa::ViewBatch.where(site: @site).order(id: :desc).limit(24)
    @shared_pools = LightekPwa::SharedPool.where(site: @site).includes(:member_backends).order(:id)
    @member_backends = LightekPwa::MemberBackend.where(site: @site).includes(:user).order(id: :desc).limit(50)
    @pool_packages = HostingPackage.includes(:product).where(active: true).order(:id)
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
  def configure_launch
    attributes = params.require(:launch_settings).permit(*LightekPwa::LaunchSettings::ENV_KEYS.keys).to_h
    LightekPwa::LaunchSetup.update!(site: @site, actor: current_user, attributes: attributes)
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Platform launch settings saved. Live acceptance checks are still required.'
  end
  def configure_webhook
    # Old open browser forms may still POST here. Do not create or rotate a
    # second payment credential from this product's setup screen.
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Payments use the existing Dymond Bank Stripe credential in Vault and /billing/webhooks/stripe. No separate payment secret is required here.'
  end
  def verify_youtube
    LightekPwa::LaunchSetup.verify_youtube!(site: @site, actor: current_user)
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'YouTube authorization matches the selected channel. A real upload and embedded playback test are still required.'
  rescue LightekPwa::YoutubeApi::Unavailable, LightekVault::Service::AccessDenied, LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError, ActiveRecord::RecordNotFound, SocketError, Timeout::Error
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), alert: 'Channel authorization could not be verified. Check the selected channel and Vault credential.'
  end
  def finalize_views
    batch = LightekPwa::ViewReconciliation.call!(site: @site, actor: current_user, month: params.require(:month),
      finalized_cents: params.require(:finalized_cents), source_reference: params.require(:source_reference),
      report: params[:report], finalized_receipt: params[:finalized_receipt], complete_channel: params[:complete_channel] == '1')
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "Finalized view batch ##{batch.id}. Creator earnings await confirmed funding."
  end
  def fund_views
    batch = LightekPwa::ViewBatch.where(site: @site).find(params.require(:batch_id))
    LightekPwa::ViewSettlement.fund!(batch: batch, actor: current_user, reference: params.require(:funding_reference))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Actual available platform funding verified and reserved for this batch.'
  end
  def create_pool
    package = HostingPackage.where(active: true).find(params.require(:package_id))
    pool = LightekPwa::MemberBackends.create_pool!(site: @site, actor: current_user, package: package,
      max_members: Integer(params.require(:max_members)), monthly_budget_cents: Integer(params.require(:monthly_budget_cents)), request_key: params.require(:request_key))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "Shared host ##{pool.id} is being installed on a separate server."
  end
  def create_smallest_pool
    pool = LightekPwa::MemberBackends.create_smallest_pool!(site: @site, actor: current_user,
      region: params.require(:region), plan_id: params.require(:plan_id),
      monthly_cents: Integer(params.require(:monthly_cents)), request_key: params.require(:request_key))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: "Shared host ##{pool.id} is being installed on a separate server."
  end
  def configure_pool_routing
    LightekPwa::MemberBackends.configure_routing!(site: @site, actor: current_user,
      mode: params.require(:mode), default_pool_id: params[:default_pool_id])
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'New-member placement updated. Existing member backends remain on their current server.'
  end
  def set_pool_status
    LightekPwa::MemberBackends.set_pool_status!(site: @site, actor: current_user,
      pool_id: params.require(:pool_id), status: params.require(:status))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Free-member server placement availability updated.'
  end
  def set_pool_account_limit
    LightekPwa::MemberBackends.set_account_limit!(site: @site, actor: current_user,
      pool_id: params.require(:pool_id), max_members: params.require(:max_members))
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Shared hosting account limit updated. No server purchase or resize was requested.'
  end
  def retry_pool
    pool = LightekPwa::SharedPool.where(site: @site).find(params.require(:pool_id))
    raise ArgumentError, 'Only an unfinished shared-host installation can be retried' unless pool.status.in?(%w[provisioning failed])
    LightekPwa::MemberPoolJob.perform_later(pool.id)
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Shared-host setup queued on its existing server. No replacement server was requested.'
  end
  def retry_backend
    backend = LightekPwa::MemberBackend.where(site: @site).find(params.require(:backend_id))
    if backend.status == 'migrating' || backend.migration_receipt['state'] == 'committed'
      LightekPwa::BackendMigrationJob.perform_later(backend.id)
    else
      LightekPwa::MemberBackendJob.perform_later(backend.id)
    end
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'Existing backend setup queued for retry.'
  end
  def rollback_backend
    backend = LightekPwa::MemberBackend.where(site: @site).find(params.require(:backend_id))
    LightekPwa::BackendMigration.new(backend, for_restore: true).rollback!
    redirect_to dashboard_pwa_revenue_path(site_id: @site.id), notice: 'The retained source is active again. The paid server is preserved for inspection.'
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
    @site = LightekPwa::Policy.sites_for(current_user).find(params.require(:site_id))
  end
end
