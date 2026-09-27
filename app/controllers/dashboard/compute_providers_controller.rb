class Dashboard::ComputeProvidersController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_provider, only: %i[show healthcheck activate disable]

  def index
    @providers = ComputeProvider.order(:name)
  end

  def show; end
  def new = (@provider = ComputeProvider.new(adapter_type: "declarative"))

  def create
    @provider = Gatekeeper::Compute::ProviderOnboardingService.create!(attributes: provider_params, requested_by: current_user.email_address)
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider added. Map capabilities and verify before activation."
  rescue StandardError => e
    @provider = ComputeProvider.new(provider_params)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def healthcheck
    result = Gatekeeper::Compute::HealthcheckService.call(provider: @provider, requested_by: current_user.email_address)
    redirect_to dashboard_compute_provider_path(@provider), notice: "Health check passed: #{result[:account] || result[:adapter] || 'connected'}."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(@provider), alert: "Health check failed: #{e.message}"
  end

  def activate
    @provider.update!(status: "active")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider activated."
  end

  def disable
    @provider.update!(status: "disabled")
    redirect_to dashboard_compute_provider_path(@provider), notice: "Provider disabled."
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_provider = (@provider = ComputeProvider.find(params[:id]))

  def provider_params
    params.require(:compute_provider).permit(:name, :slug, :adapter_type, :adapter_class, :api_base_url, :documentation_url, :openapi_url, :credential_secret_slug)
  end
end
