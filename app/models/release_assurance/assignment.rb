# frozen_string_literal: true

module ReleaseAssurance
  class Assignment < ApplicationRecord
    self.table_name = "release_assurance_assignments"

    belongs_to :tester, class_name: "ReleaseAssurance::Tester"
    belongs_to :environment, class_name: "ReleaseAssurance::Environment"

    def active?
      revoked_at.nil? && expires_at.future? && tester.offboarded_at.nil? && environment.active?
    end
  end
end
