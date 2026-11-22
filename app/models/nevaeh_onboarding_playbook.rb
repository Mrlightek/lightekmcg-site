# frozen_string_literal: true

class NevaehOnboardingPlaybook < ApplicationRecord
  belongs_to :operator, class_name: 'User'
  belongs_to :parent, class_name: 'NevaehOnboardingPlaybook', optional: true

  validates :status, inclusion: {in: %w[proposed active superseded rolled_back rejected]}
  validates :escalate_after_hours, inclusion: {in: [12, 24, 48]}
end
