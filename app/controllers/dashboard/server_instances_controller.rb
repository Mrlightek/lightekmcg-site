class Dashboard::ServerInstancesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  helper InfrastructureDashboardHelper
  protect_from_forgery with: :exception
  before_action :set_node, except: %i[index hosting]
  rescue_from Gatekeeper::Hosting::Access::Denied, ActiveRecord::RecordInvalid, with: :invalid_action

  def index
    scope = Gatekeeper::Hosting::Access.nodes(current_user)
    @launches = GatekeeperApplicationLaunch.includes(:gatekeeper_node, :gatekeeper_application_template, :provisioning_request).order(id: :desc).limit(50)
    @launches = @launches.where(owner_id: Gatekeeper::Hosting::Access.account_ids(current_user)) unless Gatekeeper::Hosting::Access.super_admin?(current_user)
    @node_counts = scope.group(:status).count
    @nodes = scope.includes(:compute_provider).order(:name).page(params[:page]).per(50)
  end

  def hosting
    Gatekeeper::Hosting::Access.nodes(current_user)
    @packages = HostingPackage.available.includes(:product).order(:id)
    @hosting_owners = User.where(id: Gatekeeper::Hosting::Access.account_ids(current_user)).order(:email_address)
  end

  def show
    @launches = GatekeeperApplicationLaunch.where(gatekeeper_node: @node).includes(:gatekeeper_application_template).order(id: :desc)
    @launches = @launches.where(owner_id: Gatekeeper::Hosting::Access.account_ids(current_user)) unless Gatekeeper::Hosting::Access.super_admin?(current_user)
    @projects = @node.gatekeeper_projects.order(:name)
    @installations = GatekeeperInstallation.where(gatekeeper_node: @node).order(:component, :domain)
    @applications = GatekeeperHostedApplication.where(gatekeeper_node: @node).order(:id)
    @applications = @applications.where(owner_id: Gatekeeper::Hosting::Access.account_ids(current_user)) unless Gatekeeper::Hosting::Access.super_admin?(current_user)
    @request = ProvisioningRequest.where(gatekeeper_node: @node).order(:id).last
    @limit = Gatekeeper::Hosting::Access.site_limit(current_user)
    @usage = Gatekeeper::Hosting::Access.site_domains(current_user).size
    @owners = if Gatekeeper::Hosting::Access.super_admin?(current_user)
      User.order(:email_address)
    elsif current_user.role == "white_label"
      User.where(id: current_user.managed_account_ids).order(:email_address)
    end
  end

  def create_application
    attributes = params.require(:application).permit(:name, :domain, :gatekeeper_project_id, :owner_id)
    owner = attributes[:owner_id].present? ? User.find(attributes[:owner_id]) : current_user
    raise Gatekeeper::Hosting::Access::Denied, "Choose an account you manage" unless Gatekeeper::Hosting::Access.manages?(current_user, owner)
    project = @node.gatekeeper_projects.find(attributes.fetch(:gatekeeper_project_id))
    Gatekeeper::Hosting::Applications.create!(actor: current_user, node: @node, project: project,
      owner: owner, name: attributes[:name], domain: attributes[:domain])
    redirect_to dashboard_server_path(@node), notice: "Application queued on this server. No new server will be created."
  end

  def retry_application
    app = GatekeeperHostedApplication.where(gatekeeper_node: @node).find(params[:application_id])
    raise Gatekeeper::Hosting::Access::Denied, "This application belongs to another account" unless Gatekeeper::Hosting::Access.super_admin?(current_user) || Gatekeeper::Hosting::Access.manages?(current_user, app.owner)
    Gatekeeper::Hosting::Applications.retry!(actor: current_user, app: app)
    redirect_to dashboard_server_path(@node), notice: "Application setup retry queued."
  end

  def destroy
    Gatekeeper::Hosting::Deletions.request!(actor: current_user, node: @node, confirmation: params[:confirmation])
    redirect_to dashboard_server_path(@node), notice: "Server deletion queued. This deletes the cloud resource and its hosted applications."
  end

  private

  def set_node
    @node = Gatekeeper::Hosting::Access.nodes(current_user).find(params[:id])
  end

  def invalid_action(error)
    redirect_to(@node ? dashboard_server_path(@node) : dashboard_servers_path, alert: error.message)
  end
end
