require "shellwords"

module Gatekeeper
  module Capabilities
    class DeployProject
      def self.call(node:, project:, parameters: {})
        raise ArgumentError, "project is required" unless project

        project.update!(status: "deploying")
        script = File.join(project.app_root, "lib/scripts/gatekeeper/deploy_project.sh")

        env = {
          APP_ROOT: project.app_root,
          APP_USER: project.app_user,
          APP_NAME: project.name,
          APP_DOMAIN: project.domain,
          APP_BRANCH: parameters["branch"].presence || project.branch,
          RUBY_VERSION: project.ruby_version,
          RAILS_ENV: project.rails_env,
          APACHE_SERVICE: project.apache_service_name,
          SIDEKIQ_SERVICE: project.sidekiq_service
        }

        prefix = env.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")
        command = "sudo #{prefix} bash #{Shellwords.escape(script)}"
        execution = CommandRunner.call(node:, command:)

        unless execution.success?
          project.update!(status: "failed")
          raise "deploy failed with exit #{execution.exit_status}: #{execution.output}"
        end

        sha = execution.stdout.to_s[/GATEKEEPER_DEPLOYED_SHA=([0-9a-f]+)/, 1]

        project.update!(
          status: "healthy",
          deployed_sha: sha.presence || project.deployed_sha,
          last_deployed_at: Time.current,
          last_healthcheck_at: Time.current
        )
        node.update!(status: "healthy", last_healthcheck_at: Time.current)

        {
          command: execution.command,
          output: execution.output,
          exit_status: execution.exit_status,
          deployed_sha: sha,
          healthy: true
        }
      end
    end
  end
end
