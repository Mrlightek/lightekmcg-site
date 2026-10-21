# frozen_string_literal: true
require 'test_helper'

class StudioCapabilityPlanResolutionV7aTest < ActiveSupport::TestCase
  RESOLVER = NevaehIntelligences::StudioCapabilityPlanResolutionV7a

  def plan
    { 'required_capability' => 'capability.build', 'capability_resolution' => 'unverified_requires_repository_and_registry_inspection',
      'execution_enabled' => false, 'gatekeeper' => { 'authorization_required' => true, 'production_execution_allowed' => false } }
  end

  test 'annotates discovery without changing original planning policy' do
    original = plan
    result = RESOLVER.attach(plan: original, capability_snapshot: [{ 'slug' => 'capability.build', 'enabled' => true }])
    assert_equal 'discovered_unverified', result.dig('studio203_evidence', 'discovery_status')
    assert_equal false, result.dig('studio203_evidence', 'execution_authorized')
    assert_equal false, result.dig('studio203_evidence', 'implementation_verified')
    assert_equal false, result.dig('studio203_evidence', 'release_approved')
    assert_equal 'unverified_requires_repository_and_registry_inspection', result['capability_resolution']
    assert_nil original['studio203_evidence']
    assert_equal false, result['execution_enabled']
  end

  test 'missing capability remains non executable' do
    result = RESOLVER.attach(plan: plan, capability_snapshot: [])
    assert_equal 'not_found', result.dig('studio203_evidence', 'discovery_status')
    assert_equal false, result.dig('studio203_evidence', 'execution_authorized')
  end

  test 'duplicate entries are rejected closed' do
    assert_raises(RESOLVER::Rejected) do
      RESOLVER.attach(plan: plan, capability_snapshot: [{ 'slug' => 'capability.build' }, { 'key' => 'capability.build' }])
    end
  end

  test 'invalid inputs and evidence overwrite are rejected' do
    assert_raises(RESOLVER::Rejected) { RESOLVER.attach(plan: {}, capability_snapshot: []) }
    assert_raises(RESOLVER::Rejected) { RESOLVER.attach(plan: plan, capability_snapshot: [{ 'slug' => '../bad' }]) }
    assert_raises(RESOLVER::Rejected) { RESOLVER.attach(plan: plan.merge('studio203_evidence' => {}), capability_snapshot: []) }
  end

  test 'stable evidence across input ordering' do
    a = RESOLVER.attach(plan: plan, capability_snapshot: [{ 'slug' => 'other' }, { 'slug' => 'capability.build' }])
    b = RESOLVER.attach(plan: plan, capability_snapshot: [{ 'slug' => 'capability.build' }, { 'slug' => 'other' }])
    assert_equal a, b
  end
end
