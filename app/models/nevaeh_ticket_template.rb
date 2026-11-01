# frozen_string_literal: true
# A user's reusable parameter bundle; the KB owns the procedure and the existing
# ticket/work-item pipeline still owns execution. Templates grant no authority.
class NevaehTicketTemplate < ApplicationRecord
  belongs_to :user
  validates :name, presence: true, length: {maximum: 160}
  validate :compile_kb_bound_sections

  def self.for_user(user)
    where(user_id: user.id)
  end

  def reusable_sections!
    NevaehIntelligences::KnowledgeProcedures.validate_steps!(sections)
    sections
  end

  private

  def compile_kb_bound_sections
    self.sections = NevaehIntelligences::StructuredTicket.compile(sections, bind_procedures: true)
  rescue NevaehIntelligences::WorkOrder::Invalid => error
    errors.add(:sections, error.message)
  end
end
