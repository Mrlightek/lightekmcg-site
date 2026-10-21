# frozen_string_literal: true

require 'json'

module NevaehIntelligences
  # An audit-only disposition. NEVER changes the execution state, retries work,
  # resolves a ticket, or grants permission to invoke a Studio handler.
  class RecoveryDecisionV2f
    class Denied < StandardError; end
    CAPABILITY = 'studio.project.create'
    ALLOWED_ACTIONS = %w[hold_for_review acknowledge_evidence].freeze

    def self.record!(ticket:, actor:, action:, reason:)
      raise Denied, 'Production recovery decisions disabled' if Rails.env.production?
      raise Denied, 'Persisted ticket required' unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise Denied, 'Persisted administrator required' unless actor.is_a?(User) && actor.persisted? && User.where(id: actor.id, role: %w[admin super_admin]).exists?
      raise Denied, 'Unsupported recovery disposition' unless ALLOWED_ACTIONS.include?(action.to_s)
      reason = reason.to_s.strip
      raise Denied, 'Written justification must be 10 to 1000 characters' unless (10..1000).cover?(reason.length)

      ticket.with_lock do
        ticket.reload
        state = ticket.extra_fields.to_h.deep_stringify_keys.fetch('nevaeh', {})
        raise Denied, 'Ticket has no recorded reservation' if state['reservation_id'].blank?
        evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
        classification = evidence.fetch('classification')
        raise Denied, 'No recovery assessment required' if classification == 'queued'
        reservation = state.fetch('reservation_id').to_s
        raise Denied, 'Evidence reservation mismatch' unless evidence['reservation_id'].to_s == reservation
        raise Denied, 'Automatic retry must remain disabled' unless evidence['automatic_retry_allowed'] == false

        # Recovery is a separate Gatekeeper policy scope. If the policy is not
        # installed or does not return an explicit allowance, fail closed.
        decision = ::Gatekeeper.authorize_capability!(
          capability: CAPABILITY,
          subject: ticket,
          context: {
            'authorization_scope' => 'nevaeh_recovery_audit_v2f',
            'actor_id' => actor.id,
            'ticket_id' => ticket.id,
            'reservation_id' => reservation,
            'classification' => classification,
            'action' => action.to_s,
            'environment' => Rails.env
          }
        )
        raise Denied, 'Gatekeeper did not explicitly authorize recovery audit' unless
          decision.respond_to?(:allowed?) && decision.allowed? &&
          decision.respond_to?(:capability) && decision.capability == CAPABILITY &&
          decision.respond_to?(:policy) && decision.policy == 'nevaeh_recovery_audit_v2f'

        detail = {
          'scope' => 'audit_only_no_execution',
          'action' => action.to_s,
          'actor_id' => actor.id,
          'reservation_id' => reservation,
          'classification' => classification,
          'work_item_ids' => evidence.fetch('work_item_ids'),
          'linked_work_item_id' => state['work_item_id'],
          'reason' => reason,
          'automatic_retry_allowed' => false,
          'recorded_at' => Time.current.iso8601
        }
        ticket.log!(action: 'nevaeh_recovery_decision_v2f', actor: actor, detail: JSON.generate(detail))
        detail
      end
    rescue ::Gatekeeper::AuthorizationDenied => e
      raise Denied, "Gatekeeper denied recovery audit: #{e.message}"
    end
  end
end
