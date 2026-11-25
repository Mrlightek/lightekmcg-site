# frozen_string_literal: true

module ReleaseAssurance
  module AcceptanceWorkflow
    VERSION = 1
    DEPENDENCIES = { "ci" => [], "browser" => [], "review" => %w[ci browser] }.freeze

    def self.start!(candidate, actor)
      Policy.runner!
      candidate.with_lock do
        Policy.authorize!(actor, candidate)
        raise Policy::Denied, "Publish the candidate before refreshing acceptance" unless
          candidate.state == "published" && Source::SHA.match?(candidate.source_sha.to_s)

        runs = candidate.workflows.where(environment: candidate.active_staging_environment)
        existing = runs.unfinished.first
        next existing if existing

        workflow = runs.create!(
          source_sha: candidate.source_sha,
          definition_version: VERSION,
          steps: DEPENDENCIES.keys.index_with { { "status" => "queued" } }
        )
        ActiveRecord.after_all_transactions_commit { enqueue(workflow) }
        workflow
      end
    end

    def self.enqueue(workflow)
      coordinator(workflow).due.each { |name| AcceptanceStepJob.perform_later(workflow.id, name) }
    rescue StandardError => error
      # The persisted work is recoverable on the next scheduler sweep.
      Rails.logger.warn("[Release Assurance] workflow=#{workflow.id} enqueue error=#{error.class.name}")
    end

    def self.coordinator(workflow)
      unless workflow.definition_version == VERSION
        raise ArgumentError, "Unsupported acceptance workflow version"
      end

      NevaehOrchestration::WorkflowSteps.new(workflow, DEPENDENCIES)
    end

    def self.authorize!(workflow)
      candidate = workflow.candidate.reload
      Policy.authorize!(candidate.operator, candidate)
      unless candidate.state == "published" && candidate.source_sha == workflow.source_sha
        raise Policy::Denied, "The published candidate revision changed."
      end
    end
  end
end
