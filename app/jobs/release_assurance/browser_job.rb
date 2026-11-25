# frozen_string_literal: true

module ReleaseAssurance
  # Existing queued browser jobs remain executable across deployments.
  class BrowserJob < ApplicationJob
    queue_as :release_assurance

    def perform(environment_id)
      Policy.runner!
      environment = Environment.find(environment_id)
      return unless environment.active?

      candidate = environment.candidate
      Policy.authorize!(candidate.operator, candidate)
      BrowserSmoke.capture(environment, candidate.source_sha) do |result, summary, screenshot|
        candidate.with_lock do
          return unless environment.reload.active?

          BrowserSmoke.record!(environment, result, summary, screenshot)
        end
      end
      Nevaeh.review!(candidate, candidate.operator)
    rescue Errno::ENOENT, Policy::Denied => error
      Rails.logger.warn("[Release Assurance] browser=#{environment_id} error=#{error.class.name}")
    end
  end
end
