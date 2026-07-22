# frozen_string_literal: true
module Marlon
  class Deliverable < ApplicationRecord
    self.table_name = "marlon_deliverables"

    STATUSES = %w[pending in_progress completed].freeze

    belongs_to :project, class_name: "Marlon::Project"

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    def complete!
      update!(status: "completed", completed_at: Time.current)
    end
  end
end
