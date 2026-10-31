# frozen_string_literal: true
class Dashboard::InstallationsController < Dashboard::SettingsHomeController
  layout "dymond_dash/layouts/dymond_dash"
  before_action { response.headers["Cache-Control"] = "no-store, private" }

  def index
    @orders = LightekCommerce::Installations.scope_for(current_user, operator: true)
      .includes(:site, items: :product).order(created_at: :desc).limit(150)
  end

  def retry_installation
    order = LightekCommerce::Installations.scope_for(current_user, operator: true).find(params.require(:id))
    LightekCommerce::Installations.resume!(order)
    redirect_to dashboard_installations_path, notice: "The existing paid installation has been queued to resume."
  rescue LightekCommerce::PaidInstanceProvisioning::NotReady
    redirect_to dashboard_installations_path, alert: "Payment must be confirmed before installation can resume."
  end
end
