# frozen_string_literal: true
require 'test_helper'
require 'json'

# Persists real User/Ticket/Capability/TicketEvent and invokes the real
# RecoveryEvidence -> Gatekeeper -> RecoveryDecision path. No work is queued.
class RecoveryPersistedAuthorizationV2fTest < ActiveSupport::TestCase
  CAPABILITY = 'studio.project.create'
  ACTION = 'nevaeh_recovery_decision_v2f'
  REASON = 'Operator reviewed missing work item evidence and requests a hold'

  def administrator
    User.create!(email_address: "v2f57-admin-#{SecureRandom.hex(10)}@example.test",
      first_name: 'V2F', last_name: 'Admin', role: 'admin', password: 'fixture-password-only')
  end

  def unauthorized_actor
    User.create!(email_address: "v2f57-client-#{SecureRandom.hex(10)}@example.test",
      first_name: 'V2F', last_name: 'Client', role: 'client', password: 'fixture-password-only')
  end

  def ticket_with_reservation
    ticket = Marlon::Ticket.create!(title: 'V2F57 recovery evidence proof',
      category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open')
    reservation = "v2f57-#{SecureRandom.uuid}"
    ticket.update!(extra_fields: ticket.extra_fields.to_h.deep_stringify_keys.merge(
      'nevaeh' => {'reservation_id' => reservation, 'dispatch_status' => 'dispatch_uncertain'}))
    [ticket.reload, reservation]
  end

  def capability!
    record = NevaehCapability.find_by(gatekeeper_capability: CAPABILITY) ||
      NevaehCapability.find_by(slug: CAPABILITY)
    return record if record
    NevaehCapability.create!(name: 'V2F57 Studio test capability', slug: CAPABILITY,
      domain: 'studio', intent_name: CAPABILITY, subject_type: 'Marlon::Ticket',
      handler: 'Studio::Workers::ProjectCreation', queue: 'default', priority: 2,
      gatekeeper_capability: CAPABILITY, enabled: true)
  end

  def with_enabled_capability
    capability = capability!
    was_enabled = capability.enabled?
    capability.update!(enabled: true) unless was_enabled
    yield capability
  ensure
    capability.update!(enabled: was_enabled) if capability && !was_enabled.nil? && capability.reload.enabled? != was_enabled
  end

  def recovery_events(ticket)
    ticket.events.where(action: ACTION)
  end

  test 'persisted administrator receives real Gatekeeper approval and writes one audit event' do
    with_enabled_capability do
      admin = administrator
      ticket, reservation = ticket_with_reservation
      evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
      assert_equal 'no_matching_work_item', evidence.fetch('classification')
      assert_equal [], evidence.fetch('work_item_ids')
      assert_equal 0, recovery_events(ticket).count
      result = NevaehIntelligences::RecoveryDecisionV2f.record!(
        ticket: ticket, actor: admin, action: 'hold_for_review', reason: REASON)
      assert_equal 'audit_only_no_execution', result.fetch('scope')
      assert_equal reservation, result.fetch('reservation_id')
      assert_equal false, result.fetch('automatic_retry_allowed')
      assert_equal 1, recovery_events(ticket).count
      event = recovery_events(ticket).last
      assert_equal admin.id, event.actor_id
      persisted = JSON.parse(event.detail)
      assert_equal 'hold_for_review', persisted.fetch('action')
      assert_equal reservation, persisted.fetch('reservation_id')
      assert_equal 'open', ticket.reload.status
    end
  end

  test 'capability revocation denies a previously eligible administrator without audit' do
    with_enabled_capability do |capability|
      admin = administrator
      ticket, = ticket_with_reservation
      capability.update!(enabled: false)
      assert_raises(NevaehIntelligences::RecoveryDecisionV2f::Denied) do
        NevaehIntelligences::RecoveryDecisionV2f.record!(
          ticket: ticket, actor: admin, action: 'hold_for_review', reason: REASON)
      end
      assert_equal 0, recovery_events(ticket).count
    end
  end

  test 'substituted persisted client is denied without recovery audit' do
    with_enabled_capability do
      ticket, = ticket_with_reservation
      assert_raises(NevaehIntelligences::RecoveryDecisionV2f::Denied) do
        NevaehIntelligences::RecoveryDecisionV2f.record!(
          ticket: ticket, actor: unauthorized_actor,
          action: 'hold_for_review', reason: REASON)
      end
      assert_equal 0, recovery_events(ticket).count
    end
  end

  test 'Gatekeeper denies tampered reservation context for persisted ticket and actor' do
    with_enabled_capability do
      admin = administrator
      ticket, reservation = ticket_with_reservation
      evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
      decision = Gatekeeper::AuthorizationService.call(capability: CAPABILITY, subject: ticket,
        context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f',
          'actor_id' => admin.id, 'ticket_id' => ticket.id,
          'reservation_id' => "#{reservation}-tampered", 'classification' => evidence.fetch('classification'),
          'action' => 'hold_for_review', 'environment' => Rails.env})
      assert decision.denied?
      assert_equal 'deny', decision.policy
      assert_equal 0, recovery_events(ticket).count
    end
  end

  test 'Gatekeeper denies tampered evidence classification without recovery audit' do
    with_enabled_capability do
      admin = administrator
      ticket, reservation = ticket_with_reservation
      decision = Gatekeeper::AuthorizationService.call(capability: CAPABILITY, subject: ticket,
        context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f',
          'actor_id' => admin.id, 'ticket_id' => ticket.id,
          'reservation_id' => reservation, 'classification' => 'completed_unverified',
          'action' => 'hold_for_review', 'environment' => Rails.env})
      assert decision.denied?
      assert_equal 0, recovery_events(ticket).count
    end
  end
end
