# frozen_string_literal: true

module ReleaseAssurance
  class SweepJob < ApplicationJob
    queue_as :release_assurance

    def perform
      return unless ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"] == "1"

      ExpirationJob.perform_later
      Candidate.where(state: "published").where(updated_at: 7.days.ago..).find_each do |candidate|
        AcceptanceJob.perform_later(candidate.id)
      end
    end
  end
end
