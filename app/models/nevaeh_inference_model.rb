# frozen_string_literal: true
class NevaehInferenceModel < ApplicationRecord
  include NevaehInference
  has_many :writing_profiles, class_name: "NevaehWritingProfile", foreign_key: :inference_model_id, dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :description, length: {maximum: 4000}
  validate :valid_definition

  private

  def valid_definition
    validate_inference_definition!
  rescue ArgumentError => error
    errors.add(:base, error.message)
  end
end
