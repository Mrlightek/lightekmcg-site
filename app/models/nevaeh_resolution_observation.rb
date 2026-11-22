# frozen_string_literal: true

class NevaehResolutionObservation < ApplicationRecord
  belongs_to :operator, class_name: 'User'
  belongs_to :playbook, class_name: 'NevaehResolutionPlaybook', optional: true

  validates :cohort, inclusion: {in: %w[baseline control candidate]}
end
