require "net/http"
require "json"
require "uri"

module Gatekeeper
  class GithubActionsService
    class ConfigurationError < StandardError; end
    class DispatchError < StandardError; end

    def self.dispatch_deploy!(project:, requested_by:, ref: nil)
      new(project:, requested_by:, ref:).dispatch_deploy!
    end

    def initialize(project:, requested_by:, ref: nil)
      @project = project
      @requested_by = requested_by.to_s
      @ref = ref.presence || project.branch.presence || "main"
    end

    def dispatch_deploy!
      raise ConfigurationError, "GITHUB_ACTIONS_TOKEN is missing" if token.blank?
      raise ConfigurationError, "GitHub repository is missing" if repository.blank?

      operation = GatekeeperOperation.create!(
        gatekeeper_node: project.gatekeeper_node,
        gatekeeper_project: project,
        capability: "deploy_project",
        requested_by: requested_by,
        parameters: { "transport" => "github_actions", "ref" => ref },
        result: { "transport" => "github_actions", "github_repository" => repository, "github_workflow" => workflow },
        status: "queued"
      )

      project.update!(status: "deploying")

      uri = URI("https://api.github.com/repos/#{repository}/actions/workflows/#{URI.encode_www_form_component(workflow)}/dispatches")
      req = Net::HTTP::Post.new(uri)
      req["Accept"] = "application/vnd.github+json"
      req["Authorization"] = "Bearer #{token}"
      req["X-GitHub-Api-Version"] = "2022-11-28"
      req["User-Agent"] = "Lightek-Gatekeeper"
      req["Content-Type"] = "application/json"
      req.body = {
        ref: ref,
        inputs: {
          project_id: project.id.to_s,
          operation_id: operation.id.to_s,
          requested_by: requested_by
        }
      }.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPNoContent)
        operation.update!(status: "failed", error_class: "GitHubDispatchError", error_message: "HTTP #{res.code}: #{res.body}", completed_at: Time.current)
        raise DispatchError, operation.error_message
      end

      operation
    end

    private

    attr_reader :project, :requested_by, :ref

    def token = ENV["GITHUB_ACTIONS_TOKEN"].presence
    def workflow = project.metadata.to_h["github_workflow"].presence || ENV.fetch("GATEKEEPER_GITHUB_WORKFLOW", "deploy-production.yml")

    def repository
      project.metadata.to_h["github_repository"].presence ||
        ENV["GATEKEEPER_GITHUB_REPOSITORY"].presence ||
        begin
          raw = project.repository.to_s.strip
          if raw.start_with?("git@github.com:")
            raw.delete_prefix("git@github.com:").delete_suffix(".git")
          elsif raw.include?("github.com/")
            raw.split("github.com/", 2).last.delete_suffix(".git")
          elsif raw.count("/") == 1
            raw
          end
        end
    end
  end
end
