require "shellwords"

module Gatekeeper
  module Capabilities
    class HealthcheckProject
      class Unhealthy < StandardError; end

      def self.call(node:, project:, parameters: {})
        raise ArgumentError, "project is required" unless project

        script = File.join(project.app_root, "lib/scripts/gatekeeper/healthcheck_project.sh")
        revision = project.deployed_sha.to_s
        repair_revision = revision if parameters["repair_failed_worker"] == true &&
          %w[healthy degraded].include?(project.status) && /\A[0-9a-f]{40}\z/.match?(revision)
        prefix = {
          APP_ROOT: project.app_root,
          APP_DOMAIN: project.domain,
          APACHE_SERVICE: project.apache_service_name,
          SIDEKIQ_SERVICE: project.sidekiq_service,
          EXPECTED_WORKER_RELEASE: repair_revision
        }.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")

        command = "sudo #{prefix} bash #{Shellwords.escape(script)}"
        execution = CommandRunner.call(node:, command:)

        unless execution.exit_status == 0
          project.update!(status: "degraded", last_healthcheck_at: Time.current)
          node.update!(status: "degraded", last_healthcheck_at: Time.current)
          raise Unhealthy, "healthcheck failed: #{execution.output}"
        end

        project.update!(status: "healthy", last_healthcheck_at: Time.current)
        node.update!(status: "healthy", last_healthcheck_at: Time.current)

        {
          command: execution.command,
          output: execution.output,
          exit_status: execution.exit_status,
          healthy: true,
          worker_recovered: execution.stdout.to_s.lines.any? { |line| line.strip == "GATEKEEPER_WORKER_RECOVERED=1" }
        }
      end
    end
  end
end
