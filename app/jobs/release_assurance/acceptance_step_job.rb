# frozen_string_literal: true

module ReleaseAssurance
  class AcceptanceStepJob < ApplicationJob
    queue_as :release_assurance

    def perform(workflow_id, name)
      Policy.runner!
      workflow = Workflow.find_by(id: workflow_id)
      return unless workflow

      coordinator = AcceptanceWorkflow.coordinator(workflow)
      token = coordinator.claim!(name)
      return unless token

      unless token == :expired
        begin
          AcceptanceWorkflow.authorize!(workflow)
          execute(workflow, name, coordinator, token)
        rescue Policy::Denied
          coordinator.finish!(name, token) { ["failed", "Access or the published revision changed."] }
        rescue StandardError => error
          coordinator.retry!(name, token)
          Rails.logger.warn("[Release Assurance] workflow=#{workflow.id} step=#{name} error=#{error.class.name}")
        end
      end
      AcceptanceWorkflow.enqueue(workflow.reload)
    end

    private

    def execute(workflow, name, coordinator, token)
      candidate = workflow.candidate
      case name
      when "ci"
        checks = GithubChecks.new(candidate)
        receipts = checks.collect
        complete(workflow, name, coordinator, token) do
          checks.record!(receipts)
          if receipts.any?(&:nil?)
            ["failed", "Some required GitHub Actions runs are missing. Refresh after they start."]
          else
            ["completed", "GitHub Actions evidence refreshed."]
          end
        end
      when "browser"
        environment = workflow.environment
        unless environment&.active?
          coordinator.finish!(name, token) do
            environment ? ["failed", "The selected staging environment is no longer active."] :
              ["skipped", "Deploy staging to run the browser check."]
          end
          return
        end

        BrowserSmoke.capture(environment, workflow.source_sha) do |result, summary, screenshot|
          complete(workflow, name, coordinator, token) do
            environment.with_lock do
              if environment.active?
                BrowserSmoke.record!(environment, result, summary, screenshot, external_id: "workflow:#{workflow.id}")
                [result == "passed" ? "completed" : "failed", summary]
              else
                ["failed", "The selected staging environment is no longer active."]
              end
            end
          end
        end
      when "review"
        complete(workflow, name, coordinator, token) do
          Nevaeh.review!(candidate, candidate.operator)
          ["completed", "Nevaeh reviewed the available evidence and recorded failures."]
        end
      end
    end

    def complete(workflow, name, coordinator, token)
      coordinator.finish!(name, token) do
        workflow.candidate.with_lock do
          AcceptanceWorkflow.authorize!(workflow)
          yield
        end
      end
    end
  end
end
