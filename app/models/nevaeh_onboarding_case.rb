# frozen_string_literal: true

class NevaehOnboardingCase < ApplicationRecord
  belongs_to :operator, class_name: 'User'
  belongs_to :trial, class_name: 'LightekAgency::Trial'
  belongs_to :order, class_name: 'LightekCommerce::Order'
  belongs_to :playbook, class_name: 'NevaehOnboardingPlaybook', optional: true

  scope :open_cases, -> { where(closed_at: nil) }
end
