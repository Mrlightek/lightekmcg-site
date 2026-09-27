class Dashboard::ComputeProviderCapabilitiesController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def update
    provider = ComputeProvider.find(params[:compute_provider_id])
    capabilities = params.fetch(:capabilities, {}).to_unsafe_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    provider.update!(capabilities: provider.capabilities.to_h.merge(capabilities), status: "validating")
    redirect_to dashboard_compute_provider_path(provider), notice: "Capabilities updated; provider is validating."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]), alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
