class Dashboard::FleetUpdatesController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_fleet_operator!
  rescue_from Gatekeeper::Fleet::Rollouts::Invalid, ActiveRecord::RecordInvalid, ArgumentError, with: :invalid_request

  def index
    @releases = GatekeeperRelease.order(created_at: :desc).limit(50)
    @installations = GatekeeperInstallation.includes(:gatekeeper_node).order(:domain)
    @rollouts = GatekeeperRollout.includes(:gatekeeper_release).order(created_at: :desc).limit(25)
  end

  def show
    @rollout = GatekeeperRollout.find(params[:id])
    @counts = @rollout.gatekeeper_update_targets.group(:status).count
    @targets = @rollout.gatekeeper_update_targets.includes(gatekeeper_installation: :gatekeeper_node).order(:id).page(params[:page]).per(100)
  end

  def sync
    Gatekeeper::Fleet::Inventory.sync!
    redirect_to dashboard_fleet_updates_path, notice: "Registered customer installations synchronized."
  end

  def installation
    installation = GatekeeperInstallation.find(params[:installation_id])
    installation.with_lock do
      raise Gatekeeper::Fleet::Rollouts::Invalid, "Cancel this installation's active rollout before changing its update policy" if
        installation.gatekeeper_update_targets.where(status: %w[reserved queued running failed]).exists?
      installation.update!(params.require(:installation).permit(:channel, :enabled, :automatic_updates))
    end
    redirect_to dashboard_fleet_updates_path, notice: "Installation update policy saved."
  end

  def release
    GatekeeperRelease.create!(params.require(:release).permit(:version, :source_sha, :image, :channel, :notes, :backward_compatible)
      .merge(created_by: current_user.email_address))
    redirect_to dashboard_fleet_updates_path, notice: "Immutable release registered."
  end

  def create
    release = GatekeeperRelease.find(params.require(:release_id))
    ids = if params[:selection] == "all"
      GatekeeperInstallation.where(enabled: true, channel: release.channel).includes(:gatekeeper_node).select(&:eligible?).map(&:id)
    else
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

  def require_fleet_operator!
    Gatekeeper::Fleet::Rollouts.authorize!(current_user)
  rescue Gatekeeper::Fleet::Rollouts::Invalid => error
    redirect_to dymond_dash.dashboard_path, alert: error.message
  end

  def invalid_request(error)
    redirect_to dashboard_fleet_updates_path, alert: error.message
  end
end
