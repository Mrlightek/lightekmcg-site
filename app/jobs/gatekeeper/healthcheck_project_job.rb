module Gatekeeper
  class HealthcheckProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id, requested_by: "gatekeeper")
      project = GatekeeperProject.find(project_id)
      Executor.call(
        capability: "healthcheck_project",
        node: project.gatekeeper_node,
        project:,
        requested_by:
      )
    end
  end
end
