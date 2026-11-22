# frozen_string_literal: true

require "securerandom"

module Gatekeeper
  module ProjectHealthMonitor
    SETTINGS_KEY = "project_health_monitor"
    INTERVAL = 15.minutes

    module_function

    def configure!(project:, actor:, enabled:)
      raise Hosting::Access::Denied, "Gatekeeper operator access required" unless Hosting::Access.super_admin?(actor)

      project.with_lock do
        metadata = project.metadata.to_h
        previous = metadata[SETTINGS_KEY]
        if enabled
          unless previous&.fetch("operator_id", nil) == actor.id
            metadata = metadata.merge(SETTINGS_KEY => {"id" => SecureRandom.uuid, "operator_id" => actor.id,
              "next_at" => Time.current.to_i})
          end
        else
          metadata = metadata.except(SETTINGS_KEY)
        end
        project.update!(metadata: metadata) if project.metadata != metadata
      end
      status(project)
    end

    def enabled_projects
      GatekeeperProject.where(status: %w[healthy degraded])
        .where("metadata -> 'project_health_monitor' ->> 'operator_id' IS NOT NULL")
    end

    def claim!(project)
      project.with_lock do
        settings = project.metadata.to_h[SETTINGS_KEY]
        return unless settings && %w[healthy degraded].include?(project.status)
        return unless settings.fetch("next_at") <= Time.current.to_i
        return unless operator_allowed?(project, settings.fetch("id"), settings.fetch("operator_id"))

        Hosting::Access.active!(project.gatekeeper_node)
        updated = settings.merge("next_at" => INTERVAL.from_now.to_i)
        project.update!(metadata: project.metadata.merge(SETTINGS_KEY => updated))
        [project.id, settings.fetch("id"), settings.fetch("operator_id"), project.gatekeeper_node_id]
      end
    rescue Hosting::Access::Denied
      nil
    end

    def operator_allowed?(project, monitor_id, operator_id)
      settings = project.metadata.to_h[SETTINGS_KEY]
      settings && settings.values_at("id", "operator_id") == [monitor_id, operator_id] &&
        Hosting::Access.super_admin?(User.find_by(id: operator_id))
    end

    def operations(project_id, node_id, monitor_id)
      GatekeeperOperation.where(gatekeeper_project_id: project_id, gatekeeper_node_id: node_id,
        capability: "healthcheck_project").where("parameters ->> 'health_monitor_id' = ?", monitor_id)
    end

    def repair_available?(project, monitor_id)
      checks = operations(project.id, project.gatekeeper_node_id, monitor_id)
      latest_pass = checks.where(status: "succeeded").maximum(:id) || 0
      checks.where("id > ?", latest_pass)
        .where("CAST(parameters ->> 'repair_failed_worker' AS TEXT) IN (?)", %w[true 1]).none?
    end

    def status(project)
      settings = project.metadata.to_h[SETTINGS_KEY]
      {"project_id" => project.id, "monitoring_enabled" => settings.present?,
        "next_check_at" => settings && Time.at(settings.fetch("next_at")).utc.iso8601}
    end
  end
end
