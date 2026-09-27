class Dashboard::ComputeProviderValidationsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def create
    provider = ComputeProvider.find(params[:compute_provider_id])

    checks = Gatekeeper::Compute::ProviderValidationService.call(
      provider: provider,
      requested_by: current_user.email_address
    )

    passed = checks.values.all? { |check| check["passed"] == true }

    redirect_to dashboard_compute_provider_path(provider),
                notice: passed ? "Read-only provider validation passed." : "Provider validation completed with failures."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]),
                alert: "Provider validation failed: #{e.message}"
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
