class Dashboard::HostingPackagesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role == "super_admin" }
  def index
    @packages = HostingPackage.includes(:product, :compute_provider, :gatekeeper_application_template).order(:id)
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @plans = DymondBank::SubscriptionPlan.order(:name)
    @providers = ComputeProvider.active.where(slug: "linode")
    GatekeeperApplicationTemplate.ensure_native!
    @templates = GatekeeperApplicationTemplate.available
  end
  def create
    values = params.require(:package).permit(:name, :site_id, :subscription_plan_id, :price_cents,
      :compute_provider_id, :gatekeeper_application_template_id, :region, :provider_plan,
      :monthly_cost_ceiling_cents, :minimum_margin_cents)
    site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(values.delete(:site_id))
    HostingPackage.transaction do
      LightekPwa::Policy.bind_platform!(site: site, actor: current_user)
      product = LightekCommerce::Product.create!(site: site, name: values.delete(:name), slug: "hosting-#{SecureRandom.hex(8)}",
        price_cents: values.delete(:price_cents), subscription_plan_id: values.delete(:subscription_plan_id),
        package_policy: (params[:package_policy]&.to_unsafe_h || {}), product_type: "lightek_instance", billing_interval: "month", track_inventory: false,
        inventory_quantity: 0, published: true)
      package = HostingPackage.create!(values.merge(product: product, active: true))
      Gatekeeper::Hosting::PackagePurchase.validate!(snapshot: package.snapshot, retail_cents: product.price_cents, actor: current_user)
    end
    redirect_to dashboard_hosting_packages_path, notice: "Retail hosting package published."
  rescue ActiveRecord::RecordInvalid, LightekAgency::PackagePolicy::Denied, Gatekeeper::Hosting::Access::Denied => error
    redirect_to dashboard_hosting_packages_path, alert: error.message
  end
  def update
    package = HostingPackage.find(params[:id])
    if params[:package].present?
      values = params.require(:package).permit(:price_cents, :minimum_margin_cents)
      Gatekeeper::Hosting::RetailPricing.update!(package: package, actor: current_user,
        price_cents: values[:price_cents], minimum_margin_cents: values[:minimum_margin_cents])
      redirect_to dashboard_hosting_packages_path, notice: "Monthly price updated for new checkouts. Existing subscriptions keep their agreed price."
    else
      package.update!(active: !package.active?)
      redirect_to dashboard_hosting_packages_path, notice: "Hosting availability updated."
    end
  rescue ActiveRecord::RecordInvalid, Gatekeeper::Hosting::Access::Denied => error
    redirect_to dashboard_hosting_packages_path, alert: error.message
  end
end
