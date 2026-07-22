# frozen_string_literal: true
module Marlon
  class Timesheet < ApplicationRecord
    self.table_name = "marlon_timesheets"

    belongs_to :project, class_name: "Marlon::Project"
    belongs_to :user

    validates :hours, numericality: { greater_than: 0 }
    validates :worked_on, presence: true
  end
end
