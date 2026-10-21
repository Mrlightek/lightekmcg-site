# frozen_string_literal: true
require 'test_helper'

# Test-only checks. No dispatch, work-item creation, or recovery audit writes.
class RecoveryPolicyIntegrityV2fTest < ActiveSupport::TestCase
  def source(path)
    File.read(Rails.root.join(path))
  end

  def gatekeeper_source
    source('app/services/gatekeeper/authorization_service.rb')
  end

  def decision_source
    source('app/services/nevaeh_intelligences/recovery_decision_v2f.rb')
  end

  def capability!
    NevaehCapability.find_by(gatekeeper_capability: 'studio.project.create') ||
      NevaehCapability.find_by(slug: 'studio.project.create') ||
      NevaehCapability.create!(name: 'V2F56 studio project', slug: 'studio.project.create',
        domain: 'studio', intent_name: 'studio.project.create', subject_type: 'Marlon::Ticket',
        handler: 'Studio::Workers::ProjectCreation', queue: 'default', priority: 2,
        gatekeeper_capability: 'studio.project.create', enabled: true)
  end

  test 'recovery scope rejects a forged ticket subject at runtime' do
    capability!
    decision = Gatekeeper::AuthorizationService.call(
      capability: 'studio.project.create', subject: Object.new,
      context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f', 'actor_id' => -1})
    assert decision.denied?
    refute_equal 'nevaeh_recovery_audit_v2f', decision.policy
  end

  test 'disabled registered capability is rejected at runtime' do
    capability = capability!
    old = capability.enabled?
    capability.update!(enabled: false)
    decision = Gatekeeper::AuthorizationService.call(
      capability: 'studio.project.create', subject: Object.new,
      context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f'})
    assert decision.denied?
  ensure
    capability.update!(enabled: old) if capability && !old.nil?
  end

  test 'policy requires persisted administrator and ticket authorization' do
    code = gatekeeper_source
    assert_includes code, 'return deny("Administrator required.")'
    assert_includes code, 'Ability.new(actor).can?(:update, @subject)'
    assert_includes code, 'context["ticket_id"].to_s == @subject.id.to_s'
  end

  test 'policy rechecks current reservation and current evidence classification' do
    code = gatekeeper_source
    assert_includes code, '@subject.reload.extra_fields'
    assert_includes code, 'return deny("Reservation mismatch.")'
    assert_includes code, 'RecoveryEvidenceV2f.for_ticket(@subject)'
    assert_includes code, 'return deny("Evidence changed.")'
    assert_includes code, 'evidence["automatic_retry_allowed"] == false'
  end

  test 'audit decision records only after explicit policy allowance under ticket lock' do
    code = decision_source
    assert_includes code, 'ticket.with_lock do'
    assert_includes code, 'decision.allowed?'
    assert_includes code, "decision.policy == 'nevaeh_recovery_audit_v2f'"
    assert_includes code, "ticket.log!(action: 'nevaeh_recovery_decision_v2f'"
    assert_operator code.index('decision.allowed?'), :<, code.index("ticket.log!(action: 'nevaeh_recovery_decision_v2f'")
  end

  test 'only audit dispositions are accepted and production stays blocked' do
    assert_equal %w[hold_for_review acknowledge_evidence], NevaehIntelligences::RecoveryDecisionV2f::ALLOWED_ACTIONS
    assert_includes gatekeeper_source, 'return deny("Recovery policy disabled in production.") if Rails.env.production?'
    assert_includes decision_source, "raise Denied, 'Production recovery decisions disabled' if Rails.env.production?"
    assert_includes decision_source, "'automatic_retry_allowed' => false"
  end
end
