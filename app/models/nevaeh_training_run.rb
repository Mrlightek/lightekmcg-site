# frozen_string_literal: true
class NevaehTrainingRun < ApplicationRecord
  belongs_to :nevaeh_language_model
  belongs_to :nevaeh_training_dataset
  belongs_to :actor, class_name: 'User'
  has_one :checkpoint, class_name: 'NevaehLanguageCheckpoint', dependent: :restrict_with_error
  validates :epochs, numericality: {only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 50}
  validates :request_key, presence: true, length: {maximum: 100}
  validates :status, inclusion: {in: %w[queued running completed failed cancelled]}
end
