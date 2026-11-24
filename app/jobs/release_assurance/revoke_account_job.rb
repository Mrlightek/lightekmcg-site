# frozen_string_literal: true

require "net/http"

module ReleaseAssurance
  class RevokeAccountJob < ApplicationJob
    queue_as :release_assurance

    retry_on Policy::Denied, IOError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
      wait: :polynomially_longer, attempts: 5

    def perform(assignment_id)
      Policy.runner!
      assignment = Assignment.find(assignment_id)
      return unless assignment.revoked_at?

      BetaAccess.revoke!(assignment)
    end
  end
end
