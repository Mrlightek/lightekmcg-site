# frozen_string_literal: true

module ReleaseAssurance
  class Environment < ApplicationRecord
    self.table_name = "release_assurance_environments"

    belongs_to :candidate, class_name: "ReleaseAssurance::Candidate"
    belongs_to :provisioning_request
    belongs_to :deployment_operation, class_name: "GatekeeperOperation", optional: true
    has_many :assignments, class_name: "ReleaseAssurance::Assignment"

    scope :expired, -> { where(expires_at: ..Time.current).where(state: %w[prepared approved ready failed retiring]) }

    def active? = state == "ready" && expires_at.future?
  end
end
