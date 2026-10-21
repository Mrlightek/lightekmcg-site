# frozen_string_literal: true

module NevaehIntelligences
  # Prepared-only Phase 6B execution service. NOT wired into DymondDispatch.
  # Requires Phase 6A migration and separate authorization/concurrency proofs.
  class TransactionalStudioCreationV2f
    class Denied < StandardError; end
    CAPABILITY = 'studio.project.create'
    HANDLER = 'Studio::Workers::ProjectCreation'

    def self.call(item:)
      raise Denied, 'Production execution disabled' if Rails.env.production?
      raise Denied, 'Incorrect WorkItem' unless item.is_a?(DymondDispatch::WorkItem) && item.persisted? &&
        item.kind.to_s == CAPABILITY && item.handler.to_s == HANDLER && item.status.to_s == 'working'
      raise Denied, 'Original ticket missing' unless item.subject_type == 'Marlon::Ticket' && item.subject_id.present?
      raise Denied, 'Reservation missing' if item.correlation_id.blank?
      raise Denied, 'Idempotency schema not installed' unless NevaehStudioIdempotencyRecord.table_exists?

      # Ticket and correlation jointly identify ONE authorized logical operation.
      # Different WorkItems for the same ticket/reservation share this key.
      key = "nevaeh:studio.project.create:ticket:#{item.subject_id}:reservation:#{item.correlation_id}"
      digest = Digest::SHA256.hexdigest(key)
      signed_lock_id = [digest[0, 16]].pack('H*').unpack1('q>')
      result = nil

      NevaehStudioIdempotencyRecord.transaction(requires_new: true) do
        connection = NevaehStudioIdempotencyRecord.connection
        raise Denied, 'PostgreSQL required' unless connection.adapter_name == 'PostgreSQL'
        # Transaction-scoped, shared by all competing WorkItems, automatically
        # released at commit/rollback. The unique index is the final authority.
        connection.execute("SELECT pg_advisory_xact_lock(#{Integer(signed_lock_id)})")
        item.reload
        NevaehIntelligences::ExecutionGateV2f.require_allowed!(item)
        ticket = Marlon::Ticket.find(item.subject_id)
        state = ticket.extra_fields.to_h.deep_stringify_keys.fetch('nevaeh')
        order = NevaehIntelligences::WorkOrder.validate!(
          ticket.extra_fields.to_h.deep_stringify_keys.fetch('nevaeh_work_order')
        )
        stored = NevaehStudioIdempotencyRecord.find_by(operation_key: key)
        if stored
          raise Denied, 'Work order revision differs' unless stored.work_order_sha256 == state.fetch('work_order_sha256')
          raise Denied, 'Inputs revision differs' unless stored.inputs_sha256 == state.fetch('inputs_sha256')
          raise Denied, 'Ticket differs' unless stored.ticket_id.to_s == ticket.id.to_s
          # The result is returned without invoking Studio again. The caller
          # must still reconcile WorkItems/tickets before marking anything done.
          result = stored.result.to_h.deep_stringify_keys.merge('idempotent_replay' => true)
        else
          inputs = order.fetch('inputs')
          output = Studio::Workers::ProjectCreation.perform('create', inputs)
          NevaehStudioIdempotencyRecord.create!(
            operation_key: key,
            ticket_id: ticket.id,
            work_order_sha256: state.fetch('work_order_sha256'),
            inputs_sha256: state.fetch('inputs_sha256'),
            work_item_id: item.id,
            studio_project_id: output.fetch('project_id'),
            production_id: output.fetch('production_id'),
            studio_scene_id: output.fetch('default_scene_id'),
            result: output
          )
          result = output
        end
      end
      result
    end
  end
end
