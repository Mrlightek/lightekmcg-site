# frozen_string_literal: true
require 'test_helper'
require 'json'
require 'securerandom'

# Persisted test database records only. No dispatch jobs or Studio handlers invoked.
class RecoveryPersistedWorkItemsV2fTest < ActiveSupport::TestCase
  ACTION = 'nevaeh_recovery_decision_v2f'
  CAPABILITY = 'studio.project.create'
  REASON = 'Administrator reviewed persisted work item evidence and requests a hold'

  def admin!
    User.create!(email_address: "phase58-#{SecureRandom.hex(12)}@example.test",
      first_name: 'Phase', last_name: 'FiftyEight', role: 'admin',
      password: 'fixture-password-only')
  end

  def ticket!
    ticket = Marlon::Ticket.create!(title: 'Phase 5.8 persisted evidence',
      category: Marlon::TicketCategories.ids.first, priority: 'medium',
      urgency: 5, status: 'open')
    reservation = "phase58-#{SecureRandom.uuid}"
    ticket.update!(extra_fields: ticket.extra_fields.to_h.deep_stringify_keys.merge(
      'nevaeh' => { 'reservation_id' => reservation,
                    'dispatch_status' => 'dispatch_uncertain' }))
    [ticket.reload, reservation]
  end

  def with_capability
    capability = NevaehCapability.find_by(gatekeeper_capability: CAPABILITY) ||
      NevaehCapability.find_by(slug: CAPABILITY)
    capability ||= NevaehCapability.create!(name: 'Phase 5.8 Studio capability',
      slug: CAPABILITY, domain: 'studio', intent_name: CAPABILITY,
      subject_type: 'Marlon::Ticket', handler: 'Studio::Workers::ProjectCreation',
      queue: 'default', priority: 2, gatekeeper_capability: CAPABILITY, enabled: true)
    previous = capability.enabled?
    capability.update!(enabled: true) unless previous
    yield
  ensure
    capability.update!(enabled: previous) if capability && !previous.nil? && capability.reload.enabled? != previous
  end

  def work_item!(ticket:, reservation:, status: 'done')
    DymondDispatch::WorkItem.create!(subject: ticket, correlation_id: reservation,
      kind: CAPABILITY, handler: 'Studio::Workers::ProjectCreation',
      queue: 'default', status: status)
  end

  def link!(ticket, work_item)
    state = ticket.reload.extra_fields.to_h.deep_stringify_keys
    state.fetch('nevaeh')['work_item_id'] = work_item.id
    ticket.update!(extra_fields: state)
  end

  def audit_count(ticket)
    ticket.events.where(action: ACTION).count
  end

  test 'real completed work item is classified and audit-only disposition is authorized' do
    with_capability do
      ticket, reservation = ticket!
      wi = work_item!(ticket: ticket, reservation: reservation)
      link!(ticket, wi)
      evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
      assert_equal 'completed_unverified', evidence.fetch('classification')
      assert_equal [wi.id], evidence.fetch('work_item_ids')
      assert_equal false, evidence.fetch('automatic_retry_allowed')
      details = NevaehIntelligences::RecoveryDecisionV2f.record!(
        ticket: ticket, actor: admin!, action: 'hold_for_review', reason: REASON)
      assert_equal 'audit_only_no_execution', details.fetch('scope')
      assert_equal 'completed_unverified', details.fetch('classification')
      assert_equal [wi.id], details.fetch('work_item_ids')
      assert_equal 1, audit_count(ticket)
      assert_equal 'open', ticket.reload.status
      assert_equal 'done', wi.reload.status
    end
  end

  test 'real duplicate work items sharing one reservation are detected before any resolution' do
    with_capability do
      ticket, reservation = ticket!
      first = work_item!(ticket: ticket, reservation: reservation)
      second = work_item!(ticket: ticket, reservation: reservation)
      link!(ticket, first)
      evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
      assert_equal 'duplicate_work_items', evidence.fetch('classification')
      assert_equal [first.id, second.id].sort, evidence.fetch('work_item_ids').sort
      assert_equal false, evidence.fetch('automatic_retry_allowed')
      assert_equal 'open', ticket.reload.status
      assert_equal 0, audit_count(ticket)
    end
  end

  test 'linked receipt pointing at a different real work item is classified as mismatch' do
    with_capability do
      ticket, reservation = ticket!
      other_ticket, other_reservation = ticket!
      wi = work_item!(ticket: ticket, reservation: reservation)
      unrelated = work_item!(ticket: other_ticket, reservation: other_reservation)
      link!(ticket, unrelated)
      evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(ticket)
      assert_equal 'linked_item_mismatch', evidence.fetch('classification')
      assert_equal [wi.id], evidence.fetch('work_item_ids')
      assert_equal false, evidence.fetch('automatic_retry_allowed')
      assert_equal 'open', ticket.reload.status
      assert_equal 0, audit_count(ticket)
    end
  end

  test 'Gatekeeper refuses substituted evidence classification for persisted duplicate items' do
    with_capability do
      ticket, reservation = ticket!
      first = work_item!(ticket: ticket, reservation: reservation)
      work_item!(ticket: ticket, reservation: reservation)
      link!(ticket, first)
      actor = admin!
      decision = Gatekeeper::AuthorizationService.call(capability: CAPABILITY, subject: ticket,
        context: { 'authorization_scope' => 'nevaeh_recovery_audit_v2f',
          'actor_id' => actor.id, 'ticket_id' => ticket.id,
          'reservation_id' => reservation, 'classification' => 'completed_unverified',
          'action' => 'hold_for_review', 'environment' => Rails.env })
      assert decision.denied?
      assert_equal 'deny', decision.policy
      assert_equal 0, audit_count(ticket)
      assert_equal 'open', ticket.reload.status
    end
  end
end
