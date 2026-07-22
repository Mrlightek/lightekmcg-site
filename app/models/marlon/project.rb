# frozen_string_literal: true
module Marlon
  class Project < ApplicationRecord
    self.table_name = "marlon_projects"

    STATUSES = %w[planning active on_hold completed cancelled].freeze

    belongs_to :client,   class_name: "User", optional: true
    belongs_to :owner,    class_name: "User", optional: true
    belongs_to :purchase, class_name: "DymondBank::Purchase", optional: true

    has_many :deliverables, class_name: "Marlon::Deliverable", dependent: :destroy
    has_many :timesheets,   class_name: "Marlon::Timesheet",   dependent: :destroy

    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :active_first, -> { order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'planning' THEN 1 ELSE 2 END"), :due_date) }

    def total_hours
      timesheets.sum(:hours)
    end
  end
end
