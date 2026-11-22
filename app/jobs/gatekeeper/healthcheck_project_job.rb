module Gatekeeper
  class HealthcheckProjectJob < ApplicationJob
    queue_as :default

    def perform(project_id, requested_by: "gatekeeper", expected_node_id: nil, operator_id: nil)
      return if operator_id && !Hosting::Access.super_admin?(User.find_by(id: operator_id))

      project = GatekeeperProject.find(project_id)
      return if expected_node_id && project.gatekeeper_node_id != expected_node_id
      Hosting::Access.active!(project.gatekeeper_node)

      Executor.call(
        capability: "healthcheck_project",
        node: project.gatekeeper_node,
        project:,
        requested_by:,
        parameters: { "healthcheck_job_id" => job_id }
      )
    rescue Capabilities::HealthcheckProject::Unhealthy
      raise unless expected_node_id

      # Executor has already persisted the failed operation and its ticket.
      retry_job(wait: 1.minute) if executions == 1
    rescue Hosting::Access::Denied
      # A server entering deletion or provisioning cannot be rechecked.
    end
  end
end
