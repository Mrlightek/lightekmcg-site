# frozen_string_literal: true
class NevaehLanguageCheckpoint < ApplicationRecord
  belongs_to :nevaeh_training_run
  belongs_to :nevaeh_language_model
  validates :status, inclusion: {in: %w[candidate verified active retired]}
  before_update do
    if %w[weights sha256 metrics nevaeh_language_model_id nevaeh_training_run_id].any? { |field| will_save_change_to_attribute?(field) }
      errors.add(:base, 'Checkpoint weights and evidence are immutable')
      throw :abort
    end
  end
end
