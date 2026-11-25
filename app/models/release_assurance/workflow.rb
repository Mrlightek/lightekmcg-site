# frozen_string_literal: true

module ReleaseAssurance
  class Workflow < ApplicationRecord
    self.table_name = "release_assurance_workflows"

    belongs_to :candidate, class_name: "ReleaseAssurance::Candidate"
    belongs_to :environment, class_name: "ReleaseAssurance::Environment", optional: true

    scope :unfinished, -> { where(finished_at: nil) }

    def status
      return "in progress" unless finished_at

      steps.values.any? { |step| step.fetch("status") == "failed" } ? "failed" : "completed"
    end
  end
end
