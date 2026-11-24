class Dashboard::ProvisioningRequestsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_super_admin!
  before_action :load_staging_options, only: %i[new prepare_staging]
  before_action :set_request, only: %i[show configure approve reject execute verify approve_destroy destroy]
  before_action :protect_staging_request!, only: %i[configure execute]

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

  def new
  end

  def prepare_staging
    request = Gatekeeper::Compute::StagingRequests.prepare!(actor: current_user,
      hostname: params.require(:hostname).to_s.strip.downcase,
      budget_cents: Integer(params.require(:budget_cents)), hours: Integer(params.require(:hours)),
      settings: params.permit(:owner, :region, :compute_vault, :owner_vault, :certificate_email)
        .to_h.transform_keys(&:upcase).transform_values { |value| value.to_s.strip })
    redirect_to dashboard_provisioning_request_path(request), status: :see_other,
      notice: "Staging request prepared for approval."
  rescue Gatekeeper::Compute::StagingRequests::Invalid, Gatekeeper::WebsiteDeployment::Invalid, ArgumentError => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  rescue LightekVault::Service::AccessDenied, Gatekeeper::Compute::Provider::ConfigurationError,
      Gatekeeper::Compute::Providers::HttpSupport::RequestError, Net::OpenTimeout, Net::ReadTimeout,
      SocketError, ActiveRecord::RecordInvalid
    flash.now[:alert] = "Could not prepare the staging request. Review its provider, Vault and owner settings."
    render :new, status: :unprocessable_entity
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
    redirect_to main_app.dashboard_server_path(@request.gatekeeper_node), status: :see_other,
      notice: "Review applications and confirm server deletion in Servers & Applications."
  end

  def destroy
    redirect_to main_app.dashboard_server_path(@request.gatekeeper_node), status: :see_other,
      notice: "Review applications and confirm server deletion in Servers & Applications."
  end

  def approve
    decide!("approved")
  end

  def reject
    decide!("rejected")
  end

  private

  def load_staging_options
    staging = Gatekeeper::Compute::StagingRequests
    @staging_owners = staging.staging_owners.map(&:email_address)
    @staging_vault = staging.vault_choices
    @staging_provider = staging.staging_provider
    @staging_compute_vault = @staging_vault.fetch("compute") - [@staging_provider&.credential_secret_slug]
    @staging_setup_ready = @staging_owners.any? && @staging_vault.fetch("owner").any? &&
      @staging_provider && @staging_compute_vault.any?
  end

  def decide!(disposition)
    @request.with_lock do
      metadata = @request.metadata
      if @request.metadata.to_h["release_assurance_staging"]
        unless @request.approval_status == "pending" && @request.execution_status == "awaiting_approval"
          raise Gatekeeper::Compute::StagingRequests::Invalid, "Only pending staging requests can be decided"
        end
        if disposition == "approved"
          data = Gatekeeper::Compute::StagingRequests.validate!(@request)
          config = Gatekeeper::WebsiteDeployment.preview(actor: current_user, record: @request, domain: data.fetch("hostname"))
          unless config["credential_slug"] == data.fetch("vault").fetch("owner") && config["owner_id"] == @request.owner_id
            raise Gatekeeper::Compute::StagingRequests::Invalid, "Staging website binding changed"
          end
        end
        metadata = Gatekeeper::Compute::StagingRequests.audit_metadata(@request, current_user, disposition)
      end

      approved = disposition == "approved"
      @request.update!(approval_status: disposition,
        execution_status: approved ? (@request.compute_provider.present? ? "ready" : "awaiting_provider") : "cancelled",
        approval_reason: approved ? "Approved by super administrator." : params[:reason].presence || "Rejected by super administrator.",
        approved_by: current_user.email_address, approved_at: Time.current, metadata: metadata)
    end
    redirect_to dashboard_provisioning_request_path(@request), status: :see_other,
      notice: "Provisioning request #{disposition}."
  rescue Gatekeeper::Compute::StagingRequests::Invalid, Gatekeeper::WebsiteDeployment::Invalid => error
    redirect_to dashboard_provisioning_request_path(@request), alert: error.message, status: :see_other
  end

  def protect_staging_request!
    return unless @request.metadata.to_h["release_assurance_staging"]

    redirect_to dashboard_provisioning_request_path(@request), status: :see_other,
      alert: "Use Release Assurance to deploy this dedicated staging request."
  end

  def require_super_admin!
    return if current_user&.role == "super_admin" && LightekPeople::LifecycleAccess.active?(current_user)
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def set_request
    @request = ProvisioningRequest.find(params[:id])
  end
end
