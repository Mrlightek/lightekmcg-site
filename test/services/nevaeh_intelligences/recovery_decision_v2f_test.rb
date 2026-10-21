# frozen_string_literal: true
require 'test_helper'

class RecoveryDecisionV2fTest < ActiveSupport::TestCase
  test 'supported dispositions do not include redispatch or forced resolution' do
    assert_equal %w[hold_for_review acknowledge_evidence], NevaehIntelligences::RecoveryDecisionV2f::ALLOWED_ACTIONS
    refute_includes NevaehIntelligences::RecoveryDecisionV2f::ALLOWED_ACTIONS, 'retry'
    refute_includes NevaehIntelligences::RecoveryDecisionV2f::ALLOWED_ACTIONS, 'resolve'
  end

  test 'missing persisted ticket is denied before any Gatekeeper call' do
    assert_raises(NevaehIntelligences::RecoveryDecisionV2f::Denied) do
      NevaehIntelligences::RecoveryDecisionV2f.record!(ticket: Object.new, actor: Object.new,
        action: 'hold_for_review', reason: 'Investigate the reservation')
    end
  end

  test 'production execution remains unconditionally blocked in this service' do
    source = File.read(Rails.root.join('app/services/nevaeh_intelligences/recovery_decision_v2f.rb'))
    assert_includes source, "raise Denied, 'Production recovery decisions disabled' if Rails.env.production?"
    assert_includes source, "'authorization_scope' => 'nevaeh_recovery_audit_v2f'"
    assert_includes source, "decision.policy == 'nevaeh_recovery_audit_v2f'"
  end
end
