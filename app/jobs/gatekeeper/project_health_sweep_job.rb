# frozen_string_literal: true

module Gatekeeper
  class ProjectHealthSweepJob < ApplicationJob
    queue_as :default

    def perform
      ProjectHealthMonitor.enabled_projects.find_each do |project|
        claim = ProjectHealthMonitor.claim!(project)
        next unless claim

        project_id, monitor_id, operator_id, node_id = claim
        HealthcheckProjectJob.perform_later(project_id, requested_by: "nevaeh_it_monitor:#{operator_id}",
          expected_node_id: node_id, operator_id: operator_id, health_monitor_id: monitor_id)
      end
    end
  end
end
