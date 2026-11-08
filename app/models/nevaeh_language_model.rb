# frozen_string_literal: true
class NevaehLanguageModel < ApplicationRecord
  include NevaehNeuralLanguage
  belongs_to :active_checkpoint, class_name: 'NevaehLanguageCheckpoint', optional: true
  has_many :training_runs, class_name: 'NevaehTrainingRun', dependent: :restrict_with_error
  has_many :checkpoints, class_name: 'NevaehLanguageCheckpoint', dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :hidden_size, inclusion: {in: [8, 16, 24, 32]}
  validates :vocabulary_limit, numericality: {only_integer: true, greater_than_or_equal_to: 32, less_than_or_equal_to: 512}
  validates :visibility, inclusion: {in: %w[internal shared]}
end
