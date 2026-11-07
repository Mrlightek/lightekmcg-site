class Dashboard::ApplicationLaunchesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  helper InfrastructureDashboardHelper
  before_action :require_operator!
  rescue_from Gatekeeper::Hosting::Access::Denied, ActiveRecord::RecordInvalid, ArgumentError, KeyError, Gatekeeper::Hosting::GithubClient::Error, LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError, LightekVault::Service::AccessDenied, with: :invalid_action

  rescue_from ActiveRecord::RecordNotUnique do
    redirect_to new_dashboard_application_launch_path, alert: "This domain has already been reserved. Review its application installation."
  end

  def new
    @registry_credentials = LightekVault::Secret.active.where("LOWER(provider) IN (?)", %w[github ghcr docker]).order(:name)
    @github_credentials = LightekVault::Secret.active.where("LOWER(provider) = ?", "github").where.not(slug: [Gatekeeper::Hosting::BuildSetup::SETTINGS_SLUG, Gatekeeper::Hosting::BuildSetup::REGISTRY_SLUG]).order(:name)
    begin
      @build_setup = Gatekeeper::Hosting::BuildSetup.settings(actor: current_user)
    rescue LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError, LightekVault::Service::AccessDenied
      @build_setup = {}
    end
    @templates = GatekeeperApplicationTemplate.available
    @builds = GatekeeperApplicationTemplate.where(build_status: %w[queued failed]).order(id: :desc).limit(20)
    @nodes = Gatekeeper::Hosting::Access.nodes(current_user).where.not(status: %w[deleting delete_failed decommissioned provisioning]).order(:name)
    @owners = User.order(:email_address)
    @providers = ComputeProvider.active.where(slug: "linode", health_status: "healthy").order(:name)
    @provider = @providers.find_by(id: params[:provider_id]) || @providers.first
    @catalog = {"plans" => [], "regions" => []}
    if @provider
      begin
        @catalog = Gatekeeper::Compute::LinodeCatalogService.call(provider: @provider, requested_by: current_user.email_address, region: params[:region])
      rescue LightekVault::Crypto::ConfigurationError => error
        @vault_error = error.message
        flash.now[:alert] = "Linode credentials could not be unlocked. #{error.message}"
      rescue LightekVault::Crypto::DecryptionError
        @vault_error = "A Vault key is available, but it cannot unlock the saved credentials. Restore this database's original key through Vault access repair."
        flash.now[:alert] = @vault_error
      rescue LightekVault::Service::AccessDenied => error
        flash.now[:alert] = "The Linode credential exists, but its Vault policy denied provider access: #{error.message}"
      rescue StandardError => error
        flash.now[:alert] = "Provider catalog unavailable (#{error.class}). Check the provider connection before creating a server."
      end
    end
  end

  def create
    launch = Gatekeeper::Hosting::Launches.create!(actor: current_user,
      attributes: params.require(:launch).permit(:template_id, :owner_id, :name, :domain, :node_id, :compute_provider_id, :region, :plan, :server_name).to_h)
    redirect_to dashboard_servers_path, notice: "#{launch.name} queued. Track installation below; new servers incur provider charges."
  end

  def setup_builds
    Gatekeeper::Hosting::BuildSetup.prepare!(actor: current_user, origin: params[:origin].presence || request.base_url,
      credential_slug: params[:github_credential_slug], dependency_slug: params[:dependency_slug], registry_slug: params[:registry_slug])
    redirect_to new_dashboard_application_launch_path, notice: "Image building connected. Callback identity, CI dependency settings and available registry credentials are configured automatically."
  end

  def build_image
    Gatekeeper::Hosting::ImageBuilds.queue!(actor: current_user,
      attributes: params.require(:build).permit(:name, :preview_domain, :source_ref, :credential_slug).to_h,
      origin: Gatekeeper::Hosting::BuildSetup.settings(actor: current_user)["origin"].presence || request.base_url)
    redirect_to new_dashboard_application_launch_path, notice: "Rails Docker build queued. The template becomes available when the build publishes its image."
  end

  def create_template
    GatekeeperApplicationTemplate.create!(params.require(:template).permit(:name, :preview_domain, :kind, :image, :container_port, :credential_slug, :rails_database, :rails_worker))
    redirect_to new_dashboard_application_launch_path, notice: "Application template saved."
  end

  def disable_template
    GatekeeperApplicationTemplate.find(params[:id]).update!(enabled: false)
    redirect_to new_dashboard_application_launch_path, notice: "Template retired. Existing applications keep their installation settings."
  end

  def retry
    launch = GatekeeperApplicationLaunch.find(params[:id])
    launch.with_lock do
      raise Gatekeeper::Hosting::Access::Denied, "Only failed installations can be retried" unless launch.status == "failed"
      launch.update!(status: "queued")
    end
    Gatekeeper::Hosting::LaunchApplicationJob.perform_later(launch.id)
    redirect_to dashboard_servers_path, notice: "Retry queued using the same server reservation."
  end

  private
  def require_operator!
    redirect_to dashboard_servers_path, alert: "A super admin installs new applications and servers. Use Add website for your existing runtime." unless Gatekeeper::Hosting::Access.super_admin?(current_user)
  end
  def invalid_action(error)
    redirect_to new_dashboard_application_launch_path, alert: error.message
  end
end
