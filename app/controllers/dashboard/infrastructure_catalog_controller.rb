class Dashboard::InfrastructureCatalogController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @profiles = ProvisioningProfile.order(:name)
    @policies = ComputePolicy.includes(:preferred_provider, :fallback_provider).order(:name)
    @nodes = GatekeeperNode.includes(:compute_provider, :provisioning_profile, :compute_policy).order(:name)
  end

  def create_profile
    ProvisioningProfile.create!(profile_params)
    redirect_to dashboard_infrastructure_catalog_path, notice: "Provisioning profile created."
  rescue StandardError => e
    redirect_to dashboard_infrastructure_catalog_path, alert: e.message
  end

  def create_policy
    ComputePolicy.create!(policy_params)
    redirect_to dashboard_infrastructure_catalog_path, notice: "Compute policy created."
  rescue StandardError => e
    redirect_to dashboard_infrastructure_catalog_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def profile_params
    raw = params.require(:provisioning_profile).permit(:name,:slug,:purpose,:os_image,:cpu_cores,:memory_mb,:disk_gb,:services,:firewall_rules).to_h
    raw["services"] = raw["services"].to_s.lines.map(&:strip).reject(&:blank?)
    raw["firewall_rules"] = raw["firewall_rules"].to_s.lines.map(&:strip).reject(&:blank?)
    raw
  end

  def policy_params
    raw = params.require(:compute_policy).permit(:name,:slug,:purpose,:preferred_provider_id,:fallback_provider_id,:monthly_cost_ceiling_cents,:automatic_approval_ceiling_cents,:allowed_regions,:required_capabilities).to_h
    raw["allowed_regions"] = raw["allowed_regions"].to_s.split(",").map(&:strip).reject(&:blank?)
    raw["required_capabilities"] = raw["required_capabilities"].to_s.split(",").map(&:strip).reject(&:blank?)
    raw
  end
end
