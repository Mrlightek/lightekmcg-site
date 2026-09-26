class Dashboard::InfrastructureController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    @nodes = GatekeeperNode.includes(:gatekeeper_projects).order(:name)
    @projects = GatekeeperProject.includes(:gatekeeper_node).order(:name)
    @operations = GatekeeperOperation
      .includes(:gatekeeper_node, :gatekeeper_project)
      .recent_first
      .limit(20)
    @metrics = Gatekeeper::Metrics.summary

    render "dashboard/infrastructure/index"
  end
end
