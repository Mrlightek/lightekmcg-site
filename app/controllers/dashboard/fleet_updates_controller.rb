class Dashboard::FleetUpdatesController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_fleet_operator!
  rescue_from Gatekeeper::Fleet::Rollouts::Invalid, ActiveRecord::RecordInvalid, ArgumentError, with: :invalid_request
  rescue_from Gatekeeper::Hosting::Access::Denied, with: :invalid_request

  def index
    @releases = GatekeeperRelease.order(created_at: :desc).limit(50)
    @agency = agency_branches.find(params[:agency_id]) if params[:agency_id].present?
    @agency_options = [["Lightek and its descendants", current_user.id]] +
      agency_branches.where(role: "white_label").order(:email_address).pluck(:email_address, :id)
    scope = GatekeeperInstallation.includes(:gatekeeper_node, :account, :pinned_release)
    scope = scope.where(account_id: @agency.descendant_account_ids) if @agency
    @installations = scope.order(:domain, :component).page(params[:page]).per(50)
    sites = DymondSite::Site.where(host: @installations.map(&:domain)).select(:id)
    @instance_peers = LightekReservations::Peer.where(site_id: sites).includes(:site, :order, :member_backend).index_by { |peer| peer.site.host }
    @rollouts = GatekeeperRollout.includes(:gatekeeper_release).order(created_at: :desc).limit(25)
    @accounts = User.order(:email_address)
    @nodes = GatekeeperNode.order(:name)
  end

  def show
    @rollout = GatekeeperRollout.find(params[:id])
    @counts = @rollout.gatekeeper_update_targets.group(:status).count
    @targets = @rollout.gatekeeper_update_targets.includes(gatekeeper_installation: :gatekeeper_node).order(:id).page(params[:page]).per(100)
  end

  def sync
    failures = Gatekeeper::Fleet::Inventory.sync!
    if failures.empty?
      redirect_to dashboard_fleet_updates_path, notice: "Registered customer installations synchronized."
    else
      redirect_to dashboard_fleet_updates_path, alert: "Inventory synchronized. Review registration errors for server IDs #{failures.first(20).join(', ')}."
    end
  end

  def open_instance
    installation = GatekeeperInstallation.find(params.require(:installation_id))
    raise Gatekeeper::Hosting::Access::Denied, "Choose a registered Lightek application." unless installation.component == "lightek_app" && installation.account_id

    site = DymondSite::Site.find_by!(host: installation.domain, tenant_type: "User", tenant_id: installation.account_id)
    code = LightekConnect::AgencyDashboard.instance_code!(actor: current_user, site: site)
    redirect_to "/connect/management?code=#{code}", status: :see_other
  end

  def installation
    installation = GatekeeperInstallation.find(params[:installation_id])
    installation.with_lock do
      raise Gatekeeper::Fleet::Rollouts::Invalid, "Cancel this installation's active rollout before changing its update policy" if
        installation.gatekeeper_update_targets.where(status: %w[reserved queued running failed]).exists?
      installation.update!(installation_attributes)
    end
    redirect_to dashboard_fleet_updates_path, notice: "Installation update policy saved."
  end

  def register_installation
    attributes = installation_attributes.merge(params.require(:installation).permit(:domain, :gatekeeper_node_id))
    GatekeeperInstallation.create!(attributes)
    redirect_to dashboard_fleet_updates_path, notice: "Installation and deployment adapter registered."
  end

  def release
    attributes = params.require(:release).permit(:version, :source_sha, :image, :channel, :notes, :backward_compatible, :adapter, :component, :repository)
    attributes[:image] = nil if attributes[:image].blank?
    GatekeeperRelease.create!(attributes
      .merge(created_by: current_user.email_address))
    redirect_to dashboard_fleet_updates_path, notice: "Immutable release registered."
  end

  def create
    release = GatekeeperRelease.find(params.require(:release_id))
    ids = if %w[all account agency].include?(params[:selection])
      scope = GatekeeperInstallation.where(enabled: true, channel: release.channel).includes(:gatekeeper_node)
      if params[:selection] == "account"
        raise ArgumentError, "Select an account" if params[:account_id].blank?
        scope = scope.where(account_id: User.find(params[:account_id]).id)
      elsif params[:selection] == "agency"
        agency = agency_branches.find(params.require(:target_agency_id))
        scope = scope.where(account_id: agency.descendant_account_ids)
      end
      scope.select { |installation| installation.accepts_release?(release) }.map(&:id)
    else
      raise ArgumentError, "Choose a rollout target type" unless params[:selection].in?([nil, "", "selected"])
      Array(params[:installation_ids]).reject(&:blank?).map { |id| Integer(id.to_s, 10) }
    end
    installations = GatekeeperInstallation.where(id: ids).to_a
    raise Gatekeeper::Fleet::Rollouts::Invalid, "Select registered installations" unless ids.uniq.size == installations.size
    options = params.permit(:canary_size, :batch_size, :scheduled_at, :auto_promote).to_h.symbolize_keys
    options[:scheduled_at] = nil if options[:scheduled_at].blank?
    rollout = Gatekeeper::Fleet::Rollouts.create!(release: release, installations: installations,
      requested_by: current_user.email_address, **options)
    redirect_to dashboard_fleet_update_path(rollout), notice: "Rollout preview created. Review targets, then start."
  end

  def control
    rollout = GatekeeperRollout.find(params[:id])
    if params[:operation] == "start"
      Gatekeeper::Fleet::Rollouts.start!(rollout)
    else
      Gatekeeper::Fleet::Rollouts.control!(rollout, params[:operation])
    end
    redirect_to dashboard_fleet_update_path(rollout), notice: "Rollout #{rollout.reload.status.humanize.downcase}."
  end

  private

  def installation_attributes
    values = params.require(:installation).permit(:channel, :enabled, :automatic_updates, :adapter, :component, :repository, :account_id, :pinned_release_id).to_h
    if params[:installation].key?(:deployment_config)
      values["deployment_config"] = JSON.parse(params[:installation][:deployment_config].presence || "{}")
      raise ArgumentError, "Deployment configuration must be a JSON object" unless values["deployment_config"].is_a?(Hash)
    end
    values
  rescue JSON::ParserError
    raise ArgumentError, "Deployment configuration is not valid JSON"
  end

  def require_fleet_operator!
    Gatekeeper::Fleet::Rollouts.authorize!(current_user)
    raise Gatekeeper::Fleet::Rollouts::Invalid, "An active operator account is required" unless LightekPeople::LifecycleAccess.active?(current_user)
  rescue Gatekeeper::Fleet::Rollouts::Invalid => error
    redirect_to dymond_dash.dashboard_path, alert: error.message
  end

  def agency_branches
    User.where(role: "white_label").or(User.where(id: current_user.id))
  end

  def invalid_request(error)
    redirect_to dashboard_fleet_updates_path, alert: error.message
  end
end
