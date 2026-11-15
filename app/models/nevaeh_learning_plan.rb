# frozen_string_literal: true
class NevaehLearningPlan < ApplicationRecord
  belongs_to :actor, class_name: 'User'
  belongs_to :language_model, class_name: 'NevaehLanguageModel'
  belongs_to :active_training_run, class_name: 'NevaehTrainingRun', optional: true
  belongs_to :nevaeh_manual_build, optional: true
  validates :name, presence: true, length: {maximum: 160}
  validates :epochs, numericality: {only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 50}
  validates :status, inclusion: {in: %w[paused running completed blocked]}
  validate do
    unless dataset_ids.is_a?(Array) && dataset_ids.length.between?(1, 2000) && dataset_ids.all? { |id| id.is_a?(Integer) && id.positive? } && dataset_ids.uniq == dataset_ids
      errors.add(:dataset_ids, 'must select distinct training batches')
    end
  end
end
