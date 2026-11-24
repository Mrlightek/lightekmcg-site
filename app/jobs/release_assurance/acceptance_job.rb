# frozen_string_literal: true

module ReleaseAssurance
  class AcceptanceJob < ApplicationJob
    queue_as :release_assurance

    def perform(candidate_id)
      candidate = Candidate.find(candidate_id)
      Policy.authorize!(candidate.operator, candidate)
      Policy.runner!
      return unless candidate.state == "published"

      checks = GithubChecks.new(candidate)
      checks.sync!
      Nevaeh.review!(candidate, candidate.operator)
    rescue GithubChecks::Unavailable, Policy::Denied => error
      Rails.logger.warn("[Release Assurance] acceptance=#{candidate_id} #{error.message}")
    end
  end
end
