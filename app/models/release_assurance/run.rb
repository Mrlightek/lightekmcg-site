# frozen_string_literal: true

module ReleaseAssurance
  class Run < ApplicationRecord
    self.table_name = "release_assurance_runs"

    belongs_to :candidate, class_name: "ReleaseAssurance::Candidate"
    belongs_to :environment, class_name: "ReleaseAssurance::Environment", optional: true
    belongs_to :assignment, class_name: "ReleaseAssurance::Assignment", optional: true

    has_one_attached :screenshot

    validates :source_sha, format: { with: Source::SHA }
    validates :kind, inclusion: { in: %w[automated simulated real_world] }
    validates :result, inclusion: { in: %w[passed failed blocked running] }
    validate :matches_candidate

    private

    def matches_candidate
      errors.add(:source_sha, "must match the candidate") unless candidate&.source_sha == source_sha
      errors.add(:environment, "must belong to the candidate") if environment && environment.candidate_id != candidate_id
      errors.add(:assignment, "must belong to the environment") if assignment && assignment.environment_id != environment_id
    end
  end
end
