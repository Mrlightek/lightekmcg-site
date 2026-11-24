# frozen_string_literal: true

module ReleaseAssurance
  class ExpirationJob < ApplicationJob
    queue_as :release_assurance

    def perform
      Policy.runner!
      Environment.expired.or(Environment.where(state: "retiring")).find_each do |environment|
        begin
          Staging.new(environment, environment.candidate.operator).retire!
        rescue StandardError => error
          environment.update!(failure: "Cleanup requires review (#{error.class.name}).")
          Rails.logger.warn("[Release Assurance] cleanup=#{environment.id} error=#{error.class.name}")
        end
      end
    end
  end
end
