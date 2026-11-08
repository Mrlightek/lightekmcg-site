# frozen_string_literal: true
class NevaehWritingProfile < ApplicationRecord
  belongs_to :inference_model, class_name: "NevaehInferenceModel", optional: true
  belongs_to :language_model, class_name: "NevaehLanguageModel", optional: true
  validates :name, presence: true, length: {maximum: 160}
  validates :provider, inclusion: {in: %w[rules inference neural]}
  validates :format, inclusion: {in: NevaehIntelligences::WritingEngine::FORMATS}
  validates :instructions, length: {maximum: 8000}
  validates :inference_model, presence: true, if: -> {provider == "inference"}
  validates :language_model, presence: true, if: -> {provider == "neural"}
  validate :valid_content

  def contract
    attributes.slice("name", "format", "provider", "inference_model_id", "language_model_id", "instructions", "templates", "examples")
  end

  private

  def valid_content
    NevaehIntelligences::WritingEngine.validate_profile!(contract)
  rescue ArgumentError => error
    errors.add(:base, error.message)
  end
end
