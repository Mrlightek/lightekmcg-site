class Dashboard::DemosController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action { response.headers['Cache-Control'] = 'no-store, private'; response.headers['Referrer-Policy'] = 'same-origin' }
  rescue_from LightekAgency::Demos::Invalid, LightekCommerce::InstallationCheckout::Invalid,
    LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    ActiveRecord::RecordInvalid, with: :invalid!
  def index
    @agencies = LightekAgency::Demos.agencies(current_user).order(:email_address)
    @agency = @agencies.find(params[:agency_id].presence || current_user.id)
    @setting = LightekAgency::DemoSetting.find_or_initialize_by(agency: @agency)
    @sites = DymondSite::Site.where(tenant: @agency).order(:name)
    @products = LightekAgency::Demos.upgrade_products(@agency)
    @demos = LightekAgency::Demo.where(agency: @agency).order(created_at: :desc).limit(100)
    @clients = @agency.agency_clients.where(role: 'client').order(:email_address)
  end
  def settings
    agency = LightekAgency::Demos.agencies(current_user).find(params.require(:agency_id))
    setting = LightekAgency::DemoSetting.find_or_initialize_by(agency: agency)
    setting.update!(params.require(:demo_setting).permit(:duration_days, :max_active, :public_enabled, :public_site_id, :upgrade_product_id))
    redirect_to dashboard_demos_path(agency_id: agency.id), notice: 'Demo settings saved.'
  end
  def create
    agency = LightekAgency::Demos.agencies(current_user).find(params.require(:agency_id))
    values = params.require(:demo).permit(:name, :first_name, :last_name, :email_address, :client_id).to_h.symbolize_keys
    client = agency.agency_clients.find(values[:client_id]) if values[:client_id].present?
    demo = LightekAgency::Demos.create!(agency: agency, values: values, existing_client: client)
    redirect_to dashboard_demo_path(demo), notice: 'Demo created on this instance. A new client receives a private password setup invitation.'
  end
  def show
    @demo = LightekAgency::Demos.scope(current_user).find_by!(public_id: params[:id])
    @setting = LightekAgency::DemoSetting.find_by(agency_id: @demo.agency_id)
    @order = @demo.upgrade_order
  end
  def upgrade
    demo = LightekAgency::Demos.scope(current_user).find_by!(public_id: params[:id])
    order = LightekAgency::DemoUpgrade.reserve!(demo: demo, actor: current_user, checkout_key: params.require(:checkout_key))
    return redirect_to installation_path(order) if order.paid_at?
    checkout = LightekCommerce::StripeCheckout.start!(order: order, success_url: installation_url(order), cancel_url: dashboard_demo_url(demo))
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  end
  private
  def invalid!(error)
    redirect_to(current_user.role.in?(%w[white_label super_admin]) ? dashboard_demos_path : dashboard_client_home_path,
      alert: error.message, status: :see_other)
  end
end
