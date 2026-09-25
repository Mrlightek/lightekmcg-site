module Gatekeeper
  class DeployProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id, requested_by: "gatekeeper", parameters: {})
      project = GatekeeperProject.find(project_id)
      Executor.call(
        capability: "deploy_project",
        node: project.gatekeeper_node,
        project:,
        requested_by:,
        parameters:
      )
    end
  end
end
