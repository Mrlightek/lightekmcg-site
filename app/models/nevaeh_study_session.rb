# frozen_string_literal: true
class NevaehStudySession < ApplicationRecord
  belongs_to :nevaeh_study_routine
  belongs_to :nevaeh_training_run, optional: true
  validates :slot, inclusion: {in: NevaehStudyRoutine::SLOTS}
  validates :status, inclusion: {in: %w[queued running completed expired blocked failed]}
  validates :local_date, :scheduled_at, :ends_at, presence: true
end
