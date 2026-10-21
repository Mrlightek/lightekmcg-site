# frozen_string_literal: true
# STUDIO-203: native Nevaeh work-order registration, no dispatch or approval.
module NevaehIntelligences
  class WorkOrderNativeAdapterV7a
    class Rejected < StandardError; end
    HISTORY_KEY = 'nevaeh_work_order_revision_history'

    class << self
      # Idempotent on valid work orders. Missing and malformed orders are repaired
      # using WorkOrder.template/validate!/attach!, retaining malformed originals.
      # All writes are atomic; no execution or authorization is performed.
      def ensure_for_ticket!(ticket:, work_type: 'build', intent_key: 'capability.build', objective:, acceptance_criteria:, inputs: {})
        raise Rejected, 'test environment only' unless Rails.env.test?
        raise Rejected, 'ticket must be persisted and unresolved' unless ticket.persisted? && ticket.status != 'resolved'
        raise Rejected, 'invalid criteria' unless acceptance_criteria.is_a?(Array) && acceptance_criteria.any?
        raise Rejected, 'invalid inputs' unless inputs.is_a?(Hash)
        raise Rejected, 'invalid objective' unless objective.is_a?(String) && !objective.strip.empty?
        ticket.with_lock do
          data = ticket.extra_fields.to_h.deep_stringify_keys
          raise Rejected, 'ticket reserved or dispatched' if data.dig('nevaeh', 'work_item_id').present? || data.dig('nevaeh', 'execution_status').present?
          if data.key?('nevaeh_work_order')
            begin
              existing = WorkOrder.read!(ticket: ticket)
              return result('reused', existing)
            rescue WorkOrder::Invalid
              # Preserve the exact prior JSON contract before replacement.
              prior = data.fetch('nevaeh_work_order')
              history = data.fetch(HISTORY_KEY, [])
              raise Rejected, 'invalid revision history' unless history.is_a?(Array) && history.length < 100
              data[HISTORY_KEY] = history + [{ 'previous_order' => prior, 'reason' => 'invalid_contract', 'replaced_at' => Time.current.iso8601 }]
              ticket.update!(extra_fields: data)
              state = 'repaired'
            end
          else
            state = 'created'
          end
          attributes = WorkOrder.template(work_type: work_type, intent_key: intent_key).merge(
            'objective' => objective,
            'inputs' => inputs.deep_stringify_keys,
            'acceptance_criteria' => acceptance_criteria,
            'execution_policy' => { 'environment' => 'test', 'approval' => 'gatekeeper' }
          )
          WorkOrder.validate!(attributes)
          attached = WorkOrder.attach!(ticket: ticket, attributes: attributes)
          raise Rejected, 'native attachment mismatch' unless WorkOrder.read!(ticket: ticket) == attached
          result(state, attached)
        end
      rescue WorkOrder::Invalid, ActiveRecord::ActiveRecordError => e
        raise Rejected, "work order registration rejected: #{e.class}"
      end

      private

      def result(state, order)
        { 'state' => state, 'work_order' => order,
          'dispatch_performed' => false, 'authorization_granted' => false,
          'release_approved' => false }.freeze
      end
    end
  end
end
