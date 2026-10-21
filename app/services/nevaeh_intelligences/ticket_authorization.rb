# frozen_string_literal: true

require 'json'

module NevaehIntelligences
  # A defense-in-depth authorization check for a persisted ticket revision.
  # This is NOT an alternative to Gatekeeper's actual execution authorization.
  class TicketAuthorization
    class Denied < StandardError; end

    def self.require_approved_revision!(ticket:, actor:)
      raise Denied, 'Persisted ticket required' unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise Denied, 'Authenticated administrator required' unless actor.is_a?(User) && actor.persisted? &&
        User.where(id: actor.id, role: %w[admin super_admin]).exists?

      ticket.reload
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      order = fields['nevaeh_work_order']
      raise Denied, 'Saved work order required' unless order.is_a?(Hash)
      NevaehIntelligences::WorkOrder.validate!(order)
      raise Denied, 'Work order is not production-scoped' unless order.dig('execution_policy', 'environment') == 'production'
      approval = fields.dig('nevaeh', 'approval')
      raise Denied, 'Trusted approval record missing' unless approval.is_a?(Hash)
      raise Denied, 'Approval is not an executed authorization grant' unless approval['scope'] == 'production_authorized'
      raise Denied, 'Approval is not active' unless approval['status'] == 'approved'
      fingerprint = NevaehIntelligences::TicketApproval.fingerprint(order)
      raise Denied, 'Work order changed since approval' unless approval['fingerprint'] == fingerprint
      approver = User.find_by(id: approval['actor_id'])
      raise Denied, 'Approver is no longer an administrator' unless approver&.admin?
      raise Denied, 'Approval timestamp missing' if approval['approved_at'].blank?
      approved_at = Time.iso8601(approval.fetch('approved_at'))
      raise Denied, 'Future approval timestamp' if approved_at > Time.current + 30.seconds
      raise Denied, 'Approval expired' if approved_at < 24.hours.ago
      reason = approval['reason'].to_s
      raise Denied, 'Approval reason missing' if reason.length < 10

      event = ticket.events.where(action: 'nevaeh_work_order_approved', actor_id: approver.id).order(id: :desc).first
      raise Denied, 'Matching approval audit event missing' unless event
      details = JSON.parse(event.detail.to_s)
      raise Denied, 'Approval event differs from stored approval' unless details['fingerprint'] == fingerprint &&
        details['reason'] == reason && details['scope'] == 'production_authorized'
      raise Denied, 'Ticket has already started execution' if fields.dig('nevaeh', 'execution_status').present? ||
        fields.dig('nevaeh', 'work_item_id').present? || ticket.status == 'resolved'
      true
    rescue JSON::ParserError, ArgumentError, KeyError, NevaehIntelligences::WorkOrder::Invalid
      raise Denied, 'Invalid approval audit evidence or work order'
    end
  end
end
