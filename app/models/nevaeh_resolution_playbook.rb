# frozen_string_literal: true

class NevaehResolutionPlaybook < ApplicationRecord
  belongs_to :operator, class_name: 'User'
  belongs_to :parent, class_name: name, optional: true

  validates :status, inclusion: {in: %w[proposed trial active superseded rolled_back declined]}
end
