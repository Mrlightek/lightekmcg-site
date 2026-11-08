# frozen_string_literal: true
class NevaehWorkflowRun < ApplicationRecord
  belongs_to :nevaeh_workflow
  belongs_to :actor, class_name: "User"
  belongs_to :ticket, class_name: "Marlon::Ticket", optional: true
  validates :request_key, presence: true, length: {maximum: 100}
  validates :status, inclusion: {in: %w[queued dispatched blocked]}

  # The ticket's verified evidence is authoritative; queue acceptance is not completion.
  def execution_status
    return status unless ticket
    fields = ticket.extra_fields.to_h
    fields.dig("nevaeh", "execution_status") || fields.dig("nevaeh_backlog", "status") || status
  end
end
