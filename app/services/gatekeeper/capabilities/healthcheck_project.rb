require "shellwords"

module Gatekeeper
  module Capabilities
    class HealthcheckProject
      def self.call(node:, project:, parameters: {})
        raise ArgumentError, "project is required" unless project

        script = File.join(project.app_root, "lib/scripts/gatekeeper/healthcheck_project.sh")
        prefix = {
          APP_ROOT: project.app_root,
          APP_DOMAIN: project.domain,
          APACHE_SERVICE: project.apache_service_name,
          SIDEKIQ_SERVICE: project.sidekiq_service
        }.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")

        command = "sudo #{prefix} bash #{Shellwords.escape(script)}"
        execution = CommandRunner.call(node:, command:)

        unless execution.success?
          project.update!(status: "degraded", last_healthcheck_at: Time.current)
          node.update!(status: "degraded", last_healthcheck_at: Time.current)
          raise "healthcheck failed: #{execution.output}"
        end

        project.update!(status: "healthy", last_healthcheck_at: Time.current)
        node.update!(status: "healthy", last_healthcheck_at: Time.current)

        {
          command: execution.command,
          output: execution.output,
          exit_status: execution.exit_status,
          healthy: true
        }
      end
    end
  end
end
