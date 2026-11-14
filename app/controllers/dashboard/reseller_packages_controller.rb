class Dashboard::ResellerPackagesController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :load_store
  rescue_from LightekAgency::PackagePolicy::Denied, LightekReservations::Federation::Client::Unavailable,
    ActiveRecord::RecordInvalid, ArgumentError, KeyError, with: :invalid_package
  def index
    data = if @remote
      @remote.request('catalog')
    else
      { 'approved' => LightekAgency::HostingCatalog.rows,
        'offers' => LightekReservations::Resource.where(site: @site, kind: 'server').includes(:product).map { |resource| LightekReservations::Federation::Catalog.serialize(resource) } }
    end
    @sources = data.fetch('approved')
    @offers = data.fetch('offers')
    @editing = @offers.find { |offer| offer['id'].to_s == params[:offer_id].to_s }
    source_id = params[:source_id].presence || @editing&.fetch('source_id', nil)
    @selected_source = @sources.find { |source| source['id'].to_s == source_id.to_s } || @sources.first
    @policy = @editing&.fetch('package_policy', nil) || @selected_source&.fetch('package_policy', nil) || LightekAgency::PackagePolicy.defaults
  end
  def create
    attributes = params.require(:offer).permit(:id, :name, :description, :source_id, :price_cents, :published, package_policy: {}).to_h
    if @remote
      @remote.request('offers', method: :post, body: {offer: attributes, brand_name: @site.name})
    else
      context = Struct.new(:site, :site_id).new(@site, @site.id)
      LightekReservations::Federation::Catalog.save!(peer: context, attributes: attributes)
    end
    redirect_to dashboard_reseller_packages_path(site_id: @site.id), notice: 'Reseller package saved. Your selling price is above the protected Lightek wholesale charge.'
  end
  private
  def load_store
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).where(tenant: current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first
    return render(plain: 'Create your agency website before building a storefront package.', status: :unprocessable_entity) unless @site
    connected = LightekReservations::Federation::Client.config(@site)
    allowed = current_user.role.in?(%w[super_admin white_label]) || (current_user.role == 'admin' && connected.present?)
    return head(:forbidden) unless allowed
    LightekAgency::PackagePolicy.authorize!(current_user, 'agency')
    @remote = LightekReservations::Federation::Client.new(@site) if connected
    response.headers['Cache-Control'] = 'private, no-store'
  end
  def invalid_package(error)
    redirect_to dashboard_reseller_packages_path(site_id: @site&.id), alert: error.message, status: :see_other
  end
end
