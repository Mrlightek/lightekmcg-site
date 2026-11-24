# frozen_string_literal: true

module ReleaseAssurance
  class DeploymentJob < ApplicationJob
    queue_as :release_assurance

    def perform(environment_id)
      environment = Environment.find(environment_id)
      Staging.new(environment, environment.candidate.operator).deploy!
    end
  end
end
