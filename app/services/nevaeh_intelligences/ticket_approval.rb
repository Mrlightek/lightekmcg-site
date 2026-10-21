# frozen_string_literal: true

require 'digest'
require 'json'

module NevaehIntelligences
  # Audit-only approval record for an immutable Work Order revision.
  # This intentionally DOES NOT enable production dispatch.
  class TicketApproval
    class Denied < StandardError; end

    def self.fingerprint(order)
      raise Denied, 'A saved work order is required' unless order.is_a?(Hash) && order.present?
      Digest::SHA256.hexdigest(JSON.generate(canonical(order)))
    end

    def self.canonical(value)
      case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |v| canonical(v) }
      when Array then value.map { |v| canonical(v) }
      else value
      end
    end
    private_class_method :canonical

    def self.approve!(ticket:, actor:, reason:)
      raise Denied, 'A persisted ticket is required' unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise Denied, 'A persisted administrator is required' unless actor.is_a?(User) && actor.persisted? && User.where(id: actor.id, role: %w[admin super_admin]).exists?
      reason = reason.to_s.strip
      raise Denied, 'A written approval reason is required' if reason.length < 10 || reason.length > 1000

      ticket.with_lock do
        raise Denied, 'Resolved tickets cannot be approved' if ticket.status == 'resolved'
        data = ticket.extra_fields.to_h.deep_stringify_keys
        raise Denied, 'Execution has already been reserved or dispatched' if data.dig('nevaeh', 'execution_status').present? || data.dig('nevaeh', 'work_item_id').present?
        order = data['nevaeh_work_order']
        # Validate the saved order; never trust a request-supplied JSON blob.
        NevaehIntelligences::WorkOrder.validate!(order)
        fp = fingerprint(order)
        prior = data.dig('nevaeh', 'approval')
        raise Denied, 'This revision is already approved' if prior.is_a?(Hash) && prior['fingerprint'] == fp && prior['status'] == 'approved'
        state = data.fetch('nevaeh', {}).merge('approval' => {
          'status' => 'approved', 'fingerprint' => fp, 'actor_id' => actor.id,
          'approved_at' => Time.current.iso8601, 'reason' => reason,
          'scope' => 'audit_only_no_production_execution'
        })
        data['nevaeh'] = state
        ticket.update!(extra_fields: data)
        ticket.log!(action: 'nevaeh_work_order_approved', actor: actor,
                    detail: {fingerprint: fp, scope: 'audit_only', reason: reason}.to_json)
        state.fetch('approval')
      end
    end

    def self.approved_revision?(ticket:)
      data = ticket.extra_fields.to_h.deep_stringify_keys
      order = data['nevaeh_work_order']
      approval = data.dig('nevaeh', 'approval')
      return false unless order.is_a?(Hash) && approval.is_a?(Hash)
      approval['status'] == 'approved' && approval['fingerprint'] == fingerprint(order) &&
        User.where(id: approval['actor_id'], role: %w[admin super_admin]).exists?
    rescue Denied
      false
    end
  end
end
