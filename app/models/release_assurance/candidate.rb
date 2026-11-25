# frozen_string_literal: true

module ReleaseAssurance
  class Candidate < ApplicationRecord
    self.table_name = "release_assurance_candidates"

    belongs_to :operator, class_name: "User"
    belongs_to :promotion_approver, class_name: "User", optional: true
    has_many :environments, class_name: "ReleaseAssurance::Environment"
    has_many :workflows, class_name: "ReleaseAssurance::Workflow"
    has_many :runs, class_name: "ReleaseAssurance::Run"
    has_many :defects, class_name: "ReleaseAssurance::Defect"

    validates :name, presence: true, length: { maximum: 120 }
    validates :profile, inclusion: { in: %w[standard msp] }
    validates :state, inclusion: { in: %w[queued assembling assembled publishing conflicted published failed] }

    def active_staging_environment
      environments.where(state: "ready").where("expires_at > ?", Time.current).order(id: :desc).first
    end

    def publication_ref = "release-candidates/#{publication_key}"
  end
end
