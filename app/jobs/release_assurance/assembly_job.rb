# frozen_string_literal: true

module ReleaseAssurance
  class AssemblyJob < ApplicationJob
    queue_as :release_assurance

    def perform(candidate_id, publish = false)
      candidate = Candidate.find(candidate_id)
      Policy.authorize!(candidate.operator, candidate)
      Policy.runner!
      expected = publish ? "assembled" : "queued"
      candidate.with_lock do
        return unless candidate.state == expected
        candidate.update!(state: publish ? "publishing" : "assembling", assembly_error: nil)
      end

      source = Source.new
      if publish
        result = source.assemble(candidate.selectors, pinned_base: candidate.base_sha, pinned_sources: candidate.sources) do |dir, sha|
          raise Source::Invalid, "Reviewed candidate revision changed" unless sha == candidate.source_sha
          source.publish!(dir, sha, candidate.publication_ref)
        end
        raise Source::Invalid, "Reviewed candidate no longer assembles" if result.fetch(:conflicts).any?
        candidate.update!(state: "published")
        AcceptanceJob.perform_later(candidate.id)
      else
        result = source.assemble(candidate.selectors)
        candidate.update!(**result, state: result.fetch(:conflicts).empty? ? "assembled" : "conflicted")
      end
    rescue Source::Invalid, Policy::Denied => error
      candidate&.update!(state: publish ? "assembled" : "failed", assembly_error: error.message)
    end
  end
end
