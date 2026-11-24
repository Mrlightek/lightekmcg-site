# frozen_string_literal: true

module ReleaseAssurance
  class Defect < ApplicationRecord
    self.table_name = "release_assurance_defects"

    belongs_to :candidate, class_name: "ReleaseAssurance::Candidate"
    belongs_to :run, class_name: "ReleaseAssurance::Run"
    belongs_to :retest, class_name: "ReleaseAssurance::Run", optional: true
  end
end
