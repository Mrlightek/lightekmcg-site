module Gatekeeper
  class CallbacksController < ApplicationController
    allow_unauthenticated_access only: :github_deployment
    skip_forgery_protection only: :github_deployment

    def github_deployment
      return unless authenticated_callback?

      payload = JSON.parse(request.raw_post.presence || "{}")
      project = if payload["project_id"].present?
                  GatekeeperProject.find(payload["project_id"])
                else
                  GatekeeperProject.find_by!(name: payload.fetch("project_name", "lightekmcg-site"))
                end

      operation = if payload["operation_id"].present?
                    GatekeeperOperation.find(payload["operation_id"])
                  else
                    GatekeeperOperation.create!(
                      gatekeeper_node: project.gatekeeper_node,
                      gatekeeper_project: project,
                      capability: "deploy_project",
                      requested_by: payload["requested_by"].presence || "github_actions",
                      parameters: { "transport" => "github_actions" },
                      result: {},
                      status: "queued"
                    )
                  end

      case payload["state"]
      when "started"
        operation.update!(status: "running", started_at: operation.started_at || Time.current, result: merged_result(operation, payload))
        project.update!(status: "deploying")
      when "succeeded"
        operation.update!(
          status: "succeeded",
          exit_status: 0,
          started_at: operation.started_at || Time.current,
          completed_at: Time.current,
          result: merged_result(operation, payload).merge("deployed_sha" => payload["sha"], "http_status" => payload["http_status"]).compact
        )
        project.update!(status: "healthy", deployed_sha: payload["sha"].presence || project.deployed_sha, last_deployed_at: Time.current, last_healthcheck_at: Time.current)
        project.gatekeeper_node.update!(status: "healthy", last_healthcheck_at: Time.current)
      when "failed"
        message = payload["error"].presence || payload["output"].presence || "GitHub Actions deployment failed"
        operation.update!(
          status: "failed",
          error_class: "GitHubActionsDeploymentFailure",
          error_message: message,
          output: payload["output"].presence || operation.output,
          started_at: operation.started_at || Time.current,
          completed_at: Time.current,
          result: merged_result(operation, payload)
        )
        project.update!(status: "failed")

        error = RuntimeError.new(message)
        knowledge = KnowledgeService.find_for_failure(operation:, error:)
        ticket = SupportTicketService.open_for_failure!(operation:, error:, knowledge_articles: knowledge)
        operation.update!(result: operation.result.to_h.merge("support_ticket_id" => ticket.id, "support_ticket_number" => ticket.number, "kb_article_ids" => knowledge.map(&:article_id)))
      else
        render json: { error: "unsupported state" }, status: :unprocessable_entity
        return
      end

      render json: { ok: true, operation_id: operation.id, status: operation.reload.status, project_id: project.id }
    rescue JSON::ParserError
      render json: { error: "invalid JSON" }, status: :bad_request
    end

    private

    def authenticated_callback?
      expected = ENV["GATEKEEPER_DEPLOY_CALLBACK_TOKEN"].to_s
      provided = request.authorization.to_s.delete_prefix("Bearer ").strip
      if expected.blank?
        head :service_unavailable
        return false
      end
      valid = provided.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      head :unauthorized unless valid
      valid
    end

    def merged_result(operation, payload)
      operation.result.to_h.merge(
        "transport" => "github_actions",
        "github_run_id" => payload["run_id"],
        "github_run_url" => payload["run_url"],
        "github_repository" => payload["repository"],
        "github_ref" => payload["ref"]
      ).compact
    end
  end
end
