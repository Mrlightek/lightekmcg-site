# frozen_string_literal: true

module LightekExperiments
  class Outcome < ApplicationRecord
    self.table_name = 'lightek_experiment_outcomes'
    belongs_to :assignment, class_name: 'LightekExperiments::Assignment'
    validates :event, inclusion: { in: ->(_) { Experience::RECORDS.keys } }
    validates :record_id, numericality: { only_integer: true, greater_than: 0 }
    attr_readonly :assignment_id, :event, :record_id
  end
end
