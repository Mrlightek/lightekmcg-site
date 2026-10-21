# frozen_string_literal: true
require 'test_helper'

class StudioCapabilityAutoMatchV7aTest < ActiveSupport::TestCase
  RESOLVER = NevaehIntelligences::StudioCapabilityAutoMatchV7a

  def plan
    { 'status' => 'planning_only', 'required_capability' => 'capability.build',
      'execution_enabled' => false,
      'gatekeeper' => { 'authorization_required' => true,
                        'production_execution_allowed' => false,
                        'human_release_approval_required' => true } }
  end

  test 'exact declared match stays unverified and unauthorized' do
    r = RESOLVER.resolve(plan: plan, capability_snapshot: [{'slug'=>'other'}, {'slug'=>'capability.build', 'enabled'=>true, 'published'=>true}])
    assert_equal 'present_active_unverified', r['matching_status']
    assert_equal 1, r['candidate_count']
    assert_equal false, r['execution_authorized']
    assert_equal false, r['implementation_verified']
    assert_equal false, r['release_approved']
  end
  test 'input order does not affect decision' do
    rows = [{'slug'=>'other'}, {'slug'=>'capability.build', 'enabled'=>true, 'published'=>true}]
    assert_equal RESOLVER.resolve(plan: plan, capability_snapshot: rows), RESOLVER.resolve(plan: plan, capability_snapshot: rows.reverse)
  end
  test 'inactive and missing are not executable' do
    assert_equal 'present_inactive_unverified', RESOLVER.resolve(plan: plan, capability_snapshot: [{'slug'=>'capability.build', 'enabled'=>false, 'published'=>true}])['matching_status']
    assert_equal 'not_found', RESOLVER.resolve(plan: plan, capability_snapshot: [])['matching_status']
  end
  test 'duplicate and conflicting identifiers fail closed' do
    assert_raises(RESOLVER::Rejected) { RESOLVER.resolve(plan:plan, capability_snapshot:[{'slug'=>'capability.build'}, {'key'=>'capability.build'}]) }
    assert_raises(RESOLVER::Rejected) { RESOLVER.resolve(plan:plan, capability_snapshot:[{'slug'=>'capability.build', 'key'=>'other'}]) }
  end
  test 'invalid metadata and policy fail closed' do
    assert_raises(RESOLVER::Rejected) { RESOLVER.resolve(plan:plan, capability_snapshot:[{'slug'=>'../unsafe'}]) }
    assert_raises(RESOLVER::Rejected) { RESOLVER.resolve(plan:plan, capability_snapshot:[{'slug'=>'capability.build', 'published'=>'yes'}]) }
    unsafe=plan; unsafe['execution_enabled']=true
    assert_raises(RESOLVER::Rejected) { RESOLVER.resolve(plan:unsafe, capability_snapshot:[]) }
  end
  test 'does not mutate inputs or inspect freeform ticket text' do
    p=plan; rows=[{'slug'=>'capability.build', 'enabled'=>true}]
    before=Marshal.dump([p,rows]); r=RESOLVER.resolve(plan:p, capability_snapshot:rows)
    assert_equal before, Marshal.dump([p,rows])
    assert_equal 'present_inactive_unverified', r['matching_status']
  end
end
