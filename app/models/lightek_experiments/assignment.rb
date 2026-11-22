# frozen_string_literal: true

module LightekExperiments
  class Assignment < ApplicationRecord
    self.table_name = 'lightek_experiment_assignments'
    belongs_to :experiment, class_name: 'LightekExperiments::Experiment'
    has_many :outcomes, class_name: 'LightekExperiments::Outcome', dependent: :restrict_with_error
    validates :arm, inclusion: { in: %w[control challenger] }
    attr_readonly :experiment_id, :visitor_digest, :arm
  end
end
