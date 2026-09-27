class Dashboard::ProvisioningRequestsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!
  before_action :set_request, only: %i[show configure approve reject execute verify approve_destroy destroy]

  def index
    @requests = ProvisioningRequest.includes(
      :owner,
      :subscription_plan,
      :provisioning_profile,
      :compute_policy,
      :compute_provider
    ).recent_first.limit(200)
  end

  def show
  end

  def create
    subscription = DymondBank::Subscription.find(params.require(:subscription_id))

    request = Gatekeeper::Compute::ProvisioningRequestBuilder.call(
      subscription: subscription,
      estimated_monthly_cost_cents: params[:estimated_monthly_cost_cents].presence&.to_i,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(request),
                notice: "Provisioning request created without executing provider billing."
  rescue StandardError => e
    redirect_to dashboard_provisioning_requests_path, alert: e.message
  end

  def configure
    @request.update!(
      selected_region: params.require(:selected_region),
      selected_plan: params.require(:selected_plan),
      selected_image: params.require(:selected_image),
      node_label: params.require(:node_label),
      estimated_monthly_cost_cents: params.require(:estimated_monthly_cost_cents).to_i,
      execution_status: "awaiting_approval",
      approval_status: "pending"
    )

    Gatekeeper::Compute::ApprovalService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning configuration saved and approval policy evaluated."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request), alert: e.message
  end

  def execute
    node = Gatekeeper::Compute::ProvisioningExecutionService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Linode #{node.provider_resource_id} created and registered as Gatekeeper node #{node.id}."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Provisioning failed: #{e.message}"
  end

  def verify
    result = Gatekeeper::Compute::NodeVerificationService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provider verification: #{result[:provider_status]} / #{result[:ipv4]}."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Verification failed: #{e.message}"
  end

  def approve_destroy
    @request.update!(
      destroy_approval_status: "approved",
      destroy_approved_by: current_user.email_address,
      destroy_approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Destruction approved. The node has NOT been destroyed yet."
  end

  def destroy
    Gatekeeper::Compute::DeprovisioningService.call(
      request: @request,
      requested_by: current_user.email_address
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provider node destroyed and Gatekeeper node decommissioned."
  rescue StandardError => e
    redirect_to dashboard_provisioning_request_path(@request),
                alert: "Destroy failed: #{e.message}"
  end

  def approve
    @request.update!(
      approval_status: "approved",
      execution_status: @request.compute_provider.present? ? "ready" : "awaiting_provider",
      approval_reason: "Approved by super administrator.",
      approved_by: current_user.email_address,
      approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning request approved. No provider resource has been created yet."
  end

  def reject
    @request.update!(
      approval_status: "rejected",
      execution_status: "cancelled",
      approval_reason: params[:reason].presence || "Rejected by super administrator.",
      approved_by: current_user.email_address,
      approved_at: Time.current
    )

    redirect_to dashboard_provisioning_request_path(@request),
                notice: "Provisioning request rejected."
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_request
    @request = ProvisioningRequest.find(params[:id])
  end
end
