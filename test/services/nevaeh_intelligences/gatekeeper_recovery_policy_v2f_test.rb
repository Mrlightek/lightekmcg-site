# frozen_string_literal: true
require 'test_helper'

class GatekeeperRecoveryPolicyV2fTest < ActiveSupport::TestCase
  def ensure_capability!
    NevaehCapability.find_by(gatekeeper_capability: 'studio.project.create') ||
      NevaehCapability.find_by(slug: 'studio.project.create') ||
      NevaehCapability.create!(name: 'Recovery test studio project', slug: 'studio.project.create',
        domain: 'studio', intent_name: 'studio.project.create', subject_type: 'Marlon::Ticket',
        handler: 'Studio::Workers::ProjectCreation', queue: 'default', priority: 2,
        gatekeeper_capability: 'studio.project.create', enabled: true)
  end

  test 'audit scope denies a forged subject' do
    ensure_capability!
    result = Gatekeeper::AuthorizationService.call(capability: 'studio.project.create', subject: Object.new,
      context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f'})
    assert result.denied?
    assert_equal 'deny', result.policy
  end

  test 'audit scope denies missing ticket and actor' do
    ensure_capability!
    result = Gatekeeper::AuthorizationService.call(capability: 'studio.project.create', subject: nil,
      context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f', 'actor_id' => -1})
    assert result.denied?
    refute_equal 'nevaeh_recovery_audit_v2f', result.policy
  end

  test 'disabled Nevaeh capability cannot authorize recovery' do
    capability = ensure_capability!
    previous = capability.enabled?
    capability.update!(enabled: false)
    result = Gatekeeper::AuthorizationService.call(capability: 'studio.project.create', subject: nil,
      context: {'authorization_scope' => 'nevaeh_recovery_audit_v2f'})
    assert result.denied?
  ensure
    capability.update!(enabled: previous) if capability && !previous.nil?
  end
end
