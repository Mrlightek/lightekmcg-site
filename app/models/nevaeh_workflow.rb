# frozen_string_literal: true
class NevaehWorkflow < ApplicationRecord
  belongs_to :creator, class_name: "User"
  has_many :runs, class_name: "NevaehWorkflowRun", dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :description, length: {maximum: 4000}
  validates :status, inclusion: {in: %w[draft active paused archived]}
  validates :interval_minutes, numericality: {only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 525600}, allow_nil: true
  validate :compiled_sections
  before_save :adjust_schedule

  private

  def compiled_sections
    self.sections = NevaehIntelligences::StructuredTicket.compile(sections)
  rescue NevaehIntelligences::WorkOrder::Invalid => error
    errors.add(:sections, error.message)
  end

  def adjust_schedule
    if status != "active" || interval_minutes.nil?
      self.next_run_at = nil
    elsif next_run_at.nil? || will_save_change_to_interval_minutes? || will_save_change_to_status?
      self.next_run_at = Time.current + interval_minutes.minutes
    end
  end
end
