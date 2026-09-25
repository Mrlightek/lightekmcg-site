#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }
[[ -f app/models/gatekeeper_operation.rb ]] || { echo "ERROR: Gatekeeper foundation is not installed"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_github_cicd_backup_${STAMP}"
mkdir -p "$BACKUP"

for f in config/routes.rb app/controllers/gatekeeper/projects_controller.rb app/views/gatekeeper/projects/show.html.erb .github/workflows/deploy-production.yml; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

mkdir -p app/services/gatekeeper app/controllers/gatekeeper .github/workflows lib/scripts/gatekeeper

cat > app/services/gatekeeper/github_actions_service.rb <<'RUBY'
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
RUBY

cat > app/controllers/gatekeeper/callbacks_controller.rb <<'RUBY'
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
RUBY

python3 - <<'PY'
from pathlib import Path
p=Path('app/controllers/gatekeeper/projects_controller.rb')
s=p.read_text()
s=s.replace('before_action :set_project, only: %i[show edit update destroy deploy healthcheck]', 'before_action :set_project, only: %i[show edit update destroy deploy deploy_github healthcheck]')
if 'def deploy_github' not in s:
    marker='    def healthcheck\n'
    method='''    def deploy_github\n      operation = GithubActionsService.dispatch_deploy!(project: @project, requested_by: requester_name, ref: @project.branch)\n      redirect_to gatekeeper_project_path(@project), notice: "GitHub Actions deployment queued as Gatekeeper operation ##{operation.id}."\n    rescue Gatekeeper::GithubActionsService::ConfigurationError, Gatekeeper::GithubActionsService::DispatchError => e\n      redirect_to gatekeeper_project_path(@project), alert: "GitHub deployment could not be queued: #{e.message}"\n    end\n\n'''
    if marker not in s: raise SystemExit('ERROR: healthcheck action not found')
    s=s.replace(marker, method+marker, 1)
p.write_text(s)

p=Path('config/routes.rb')
s=p.read_text()
if 'post :deploy_github' not in s:
    s=s.replace('      post :deploy\n      post :healthcheck\n', '      post :deploy\n      post :deploy_github\n      post :healthcheck\n', 1)
if 'github_deployment_callback' not in s:
    s=s.replace('namespace :gatekeeper do\n', 'namespace :gatekeeper do\n  post "callbacks/github_deployment", to: "callbacks#github_deployment", as: :github_deployment_callback\n', 1)
p.write_text(s)

p=Path('app/views/gatekeeper/projects/show.html.erb')
s=p.read_text()
if 'deploy_github_gatekeeper_project_path' not in s:
    s=s.replace('<%= button_to "Deploy", deploy_gatekeeper_project_path(@project), method: :post %>', '<%= button_to "Deploy Direct", deploy_gatekeeper_project_path(@project), method: :post %>\n  <%= button_to "Deploy via GitHub Actions", deploy_github_gatekeeper_project_path(@project), method: :post %>', 1)
p.write_text(s)
PY

cat > .github/workflows/deploy-production.yml <<'YAML'
name: Deploy Production

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      project_id:
        required: false
        type: string
      operation_id:
        required: false
        type: string
      requested_by:
        required: false
        default: gatekeeper
        type: string

concurrency:
  group: lightekmcg-production
  cancel-in-progress: false

permissions:
  contents: read

env:
  APP_NAME: lightekmcg-site
  APP_ROOT: /var/www/lightekmcg-site
  APP_USER: lightek
  APP_DOMAIN: lightekmcg.com
  APP_BRANCH: main
  RUBY_VERSION: 3.3.6
  APACHE_SERVICE: apache2
  SIDEKIQ_SERVICE: lightekmcg-site-sidekiq
  ENV_FILE: /etc/lightek/lightekmcg-site.env

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Configure SSH
        env:
          SSH_KEY: ${{ secrets.PRODUCTION_SSH_KEY }}
          SSH_HOST: ${{ secrets.PRODUCTION_HOST }}
          SSH_PORT: ${{ secrets.PRODUCTION_SSH_PORT }}
        run: |
          set -euo pipefail
          mkdir -p ~/.ssh
          chmod 700 ~/.ssh
          printf '%s\n' "$SSH_KEY" > ~/.ssh/lightek_deploy
          chmod 600 ~/.ssh/lightek_deploy
          ssh-keyscan -p "${SSH_PORT:-22}" -H "$SSH_HOST" >> ~/.ssh/known_hosts

      - name: Notify Gatekeeper started
        id: start
        continue-on-error: true
        env:
          CALLBACK_URL: ${{ vars.GATEKEEPER_CALLBACK_URL }}
          CALLBACK_TOKEN: ${{ secrets.GATEKEEPER_DEPLOY_CALLBACK_TOKEN }}
          INPUT_PROJECT_ID: ${{ inputs.project_id }}
          INPUT_OPERATION_ID: ${{ inputs.operation_id }}
          INPUT_REQUESTED_BY: ${{ inputs.requested_by }}
        run: |
          set -euo pipefail
          [[ -n "${CALLBACK_URL:-}" && -n "${CALLBACK_TOKEN:-}" ]] || exit 0
          REQUESTED_BY="${INPUT_REQUESTED_BY:-github_push:${GITHUB_ACTOR}}"
          PAYLOAD=$(jq -n --arg state started --arg project_id "${INPUT_PROJECT_ID:-}" --arg operation_id "${INPUT_OPERATION_ID:-}" --arg requested_by "$REQUESTED_BY" --arg repository "$GITHUB_REPOSITORY" --arg ref "$GITHUB_REF_NAME" --arg run_id "$GITHUB_RUN_ID" --arg run_url "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" '{state:$state,project_id:(if $project_id=="" then null else $project_id end),project_name:"lightekmcg-site",operation_id:(if $operation_id=="" then null else $operation_id end),requested_by:$requested_by,repository:$repository,ref:$ref,run_id:$run_id,run_url:$run_url}')
          RESPONSE=$(curl --fail-with-body -sS -X POST "$CALLBACK_URL" -H "Authorization: Bearer $CALLBACK_TOKEN" -H "Content-Type: application/json" --data "$PAYLOAD")
          echo "$RESPONSE"
          OP_ID=$(echo "$RESPONSE" | jq -r '.operation_id // empty')
          [[ -z "$OP_ID" ]] || echo "GATEKEEPER_OPERATION_ID=$OP_ID" >> "$GITHUB_ENV"

      - name: Deploy production
        id: deploy
        env:
          SSH_HOST: ${{ secrets.PRODUCTION_HOST }}
          SSH_USER: ${{ secrets.PRODUCTION_USER }}
          SSH_PORT: ${{ secrets.PRODUCTION_SSH_PORT }}
        run: |
          set -euo pipefail
          ssh -i ~/.ssh/lightek_deploy -p "${SSH_PORT:-22}" -o BatchMode=yes "$SSH_USER@$SSH_HOST" \
            "APP_ROOT='$APP_ROOT' APP_USER='$APP_USER' APP_NAME='$APP_NAME' APP_DOMAIN='$APP_DOMAIN' APP_BRANCH='$APP_BRANCH' RUBY_VERSION='$RUBY_VERSION' APACHE_SERVICE='$APACHE_SERVICE' SIDEKIQ_SERVICE='$SIDEKIQ_SERVICE' ENV_FILE='$ENV_FILE' bash '$APP_ROOT/lib/scripts/gatekeeper/deploy_project.sh'" | tee deploy-output.txt
          echo "sha=$(grep '^GATEKEEPER_DEPLOYED_SHA=' deploy-output.txt | tail -1 | cut -d= -f2-)" >> "$GITHUB_OUTPUT"
          echo "http=$(grep '^GATEKEEPER_HTTP_STATUS=' deploy-output.txt | tail -1 | cut -d= -f2-)" >> "$GITHUB_OUTPUT"

      - name: Notify Gatekeeper succeeded
        if: success()
        continue-on-error: true
        env:
          CALLBACK_URL: ${{ vars.GATEKEEPER_CALLBACK_URL }}
          CALLBACK_TOKEN: ${{ secrets.GATEKEEPER_DEPLOY_CALLBACK_TOKEN }}
          INPUT_PROJECT_ID: ${{ inputs.project_id }}
          INPUT_OPERATION_ID: ${{ inputs.operation_id }}
          INPUT_REQUESTED_BY: ${{ inputs.requested_by }}
          DEPLOYED_SHA: ${{ steps.deploy.outputs.sha }}
          HTTP_STATUS: ${{ steps.deploy.outputs.http }}
        run: |
          set -euo pipefail
          [[ -n "${CALLBACK_URL:-}" && -n "${CALLBACK_TOKEN:-}" ]] || exit 0
          OP_ID="${GATEKEEPER_OPERATION_ID:-${INPUT_OPERATION_ID:-}}"
          REQUESTED_BY="${INPUT_REQUESTED_BY:-github_push:${GITHUB_ACTOR}}"
          jq -n --arg state succeeded --arg project_id "${INPUT_PROJECT_ID:-}" --arg operation_id "$OP_ID" --arg requested_by "$REQUESTED_BY" --arg repository "$GITHUB_REPOSITORY" --arg ref "$GITHUB_REF_NAME" --arg run_id "$GITHUB_RUN_ID" --arg run_url "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" --arg sha "$DEPLOYED_SHA" --arg http_status "$HTTP_STATUS" '{state:$state,project_id:(if $project_id=="" then null else $project_id end),project_name:"lightekmcg-site",operation_id:(if $operation_id=="" then null else $operation_id end),requested_by:$requested_by,repository:$repository,ref:$ref,run_id:$run_id,run_url:$run_url,sha:$sha,http_status:$http_status}' > callback.json
          curl --fail-with-body -sS -X POST "$CALLBACK_URL" -H "Authorization: Bearer $CALLBACK_TOKEN" -H "Content-Type: application/json" --data @callback.json

      - name: Notify Gatekeeper failed
        if: failure()
        continue-on-error: true
        env:
          CALLBACK_URL: ${{ vars.GATEKEEPER_CALLBACK_URL }}
          CALLBACK_TOKEN: ${{ secrets.GATEKEEPER_DEPLOY_CALLBACK_TOKEN }}
          INPUT_PROJECT_ID: ${{ inputs.project_id }}
          INPUT_OPERATION_ID: ${{ inputs.operation_id }}
          INPUT_REQUESTED_BY: ${{ inputs.requested_by }}
        run: |
          set -euo pipefail
          [[ -n "${CALLBACK_URL:-}" && -n "${CALLBACK_TOKEN:-}" ]] || exit 0
          OP_ID="${GATEKEEPER_OPERATION_ID:-${INPUT_OPERATION_ID:-}}"
          REQUESTED_BY="${INPUT_REQUESTED_BY:-github_push:${GITHUB_ACTOR}}"
          OUTPUT=""; [[ ! -f deploy-output.txt ]] || OUTPUT=$(tail -c 12000 deploy-output.txt)
          jq -n --arg state failed --arg project_id "${INPUT_PROJECT_ID:-}" --arg operation_id "$OP_ID" --arg requested_by "$REQUESTED_BY" --arg repository "$GITHUB_REPOSITORY" --arg ref "$GITHUB_REF_NAME" --arg run_id "$GITHUB_RUN_ID" --arg run_url "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" --arg output "$OUTPUT" --arg error "GitHub Actions production deployment failed" '{state:$state,project_id:(if $project_id=="" then null else $project_id end),project_name:"lightekmcg-site",operation_id:(if $operation_id=="" then null else $operation_id end),requested_by:$requested_by,repository:$repository,ref:$ref,run_id:$run_id,run_url:$run_url,output:$output,error:$error}' > callback.json
          curl --fail-with-body -sS -X POST "$CALLBACK_URL" -H "Authorization: Bearer $CALLBACK_TOKEN" -H "Content-Type: application/json" --data @callback.json
YAML

cat > lib/scripts/gatekeeper/configure_github_cicd_server.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="${APP_NAME:-lightekmcg-site}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "ERROR: missing $ENV_FILE"; exit 1; }
if ! grep -q '^GATEKEEPER_DEPLOY_CALLBACK_TOKEN=' "$ENV_FILE"; then
  printf '\nGATEKEEPER_DEPLOY_CALLBACK_TOKEN="%s"\n' "$(openssl rand -hex 32)" >> "$ENV_FILE"
fi
if ! grep -q '^GATEKEEPER_GITHUB_WORKFLOW=' "$ENV_FILE"; then
  printf 'GATEKEEPER_GITHUB_WORKFLOW="deploy-production.yml"\n' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
echo "Server CI/CD environment prepared."
BASH
chmod +x lib/scripts/gatekeeper/configure_github_cicd_server.sh

echo
echo "=== Syntax checks ==="
ruby -c app/services/gatekeeper/github_actions_service.rb
ruby -c app/controllers/gatekeeper/callbacks_controller.rb
ruby -c app/controllers/gatekeeper/projects_controller.rb
bash -n lib/scripts/gatekeeper/configure_github_cicd_server.sh
git diff --check

echo
echo "Gatekeeper GitHub Actions CI/CD installed."
echo "Backup: $BACKUP"
echo "Configure GitHub secrets BEFORE pushing this commit."
