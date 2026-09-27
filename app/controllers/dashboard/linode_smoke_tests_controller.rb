class Dashboard::LinodeSmokeTestsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def create
    provider = ComputeProvider.find(params.require(:compute_provider_id))
    raise ArgumentError, "Provider must be Linode" unless provider.slug == "linode"

    profile = ProvisioningProfile.find_by(slug: params[:profile_slug].presence || "personal_cloud") ||
      raise(ArgumentError, "Provisioning profile not found")

    catalog = Gatekeeper::Compute::LinodeCatalogService.call(
      provider: provider,
      requested_by: current_user.email_address,
      profile: profile,
      region: params[:region]
    )

    recommended = catalog.fetch("recommended_plan")
    region = params[:region].presence ||
      Array(catalog["regions"]).find { |item| item["status"].to_s == "ok" }&.fetch("id", nil) ||
      Array(catalog["regions"]).first&.fetch("id", nil)

    image = params[:image].presence ||
      Array(catalog["images"]).find { |item| item["id"] == "linode/ubuntu24.04" }&.fetch("id", nil) ||
      Array(catalog["images"]).find { |item| item["id"].to_s.include?("ubuntu") }&.fetch("id", nil)

    request = ProvisioningRequest.create!(
      owner: current_user,
      provisioning_profile: profile,
      compute_policy: ComputePolicy.find_by(slug: "lightek_production"),
      compute_provider: provider,
      requested_node_count: 1,
      selected_region: region,
      selected_plan: recommended.fetch("id"),
      selected_image: image,
      node_label: "lightek-smoke-#{Time.current.strftime("%Y%m%d%H%M%S")}",
      estimated_monthly_cost_cents: recommended.fetch("monthly_cents"),
      approval_status: "pending",
      execution_status: "awaiting_approval",
      metadata: {
        "smoke_test" => true,
        "catalog_snapshot" => {
          "recommended_plan" => recommended,
          "region" => region,
          "image" => image
        }
      }
    )

    redirect_to dashboard_provisioning_request_path(request),
                notice: "Billable smoke-test request created. Review cost and approve before execution."
  rescue StandardError => e
    redirect_to dashboard_compute_provider_path(params[:compute_provider_id]),
                alert: "Could not create smoke test: #{e.message}"
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end
end
