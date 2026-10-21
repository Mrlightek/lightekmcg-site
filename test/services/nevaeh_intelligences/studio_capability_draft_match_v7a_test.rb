# frozen_string_literal: true
require 'test_helper'

class StudioCapabilityDraftMatchV7aTest < ActiveSupport::TestCase
  SERVICE = NevaehIntelligences::StudioCapabilityDraftMatchV7a
  MATCHER = NevaehIntelligences::StudioCapabilityAutoMatchV7a
  def plan
    {'ticket_id'=>46, 'tracking_key'=>'STUDIO-203', 'fingerprint'=>'hash',
      'status'=>'planning_only', 'required_capability'=>'capability.build', 'execution_enabled'=>false,
      'gatekeeper'=>{'authorization_required'=>true, 'production_execution_allowed'=>false,
                     'human_release_approval_required'=>true}}
  end
  def draft
    {'ticket_id'=>46, 'tracking_key'=>'STUDIO-203', 'development_plan_fingerprint'=>'hash',
     'status'=>'review_only', 'gatekeeper_approved'=>false, 'executable'=>false,
     'production_allowed'=>false, 'studio_capability_engineering_plan'=>{'ticket_id'=>46}}
  end
  def resolve(p=plan, rows=[])
    MATCHER.resolve(plan:p, capability_snapshot:rows)
  end
  test 'attaches exact-match evidence and stays unauthorized' do
    p=plan; d=draft; m=resolve(p,[{'slug'=>'capability.build','enabled'=>true,'published'=>true}])
    out=SERVICE.attach(draft:d,plan:p,match:m)
    assert_equal 'present_active_unverified', out.dig('studio_capability_exact_match','matching_status')
    assert_equal false, out.dig('studio_capability_exact_match','execution_authorized')
    assert_equal false, out['gatekeeper_approved']
    assert_equal false, out['executable']
  end
  test 'inactive and missing statuses remain non-executable' do
    p=plan
    [[],[{'slug'=>'capability.build','enabled'=>false,'published'=>true}]].each do |rows|
      out=SERVICE.attach(draft:draft,plan:p,match:resolve(p,rows))
      assert_equal false,out['executable']
      assert_equal false,out.dig('studio_capability_exact_match','execution_authorized')
    end
  end
  test 'does not mutate source objects' do
    p=plan; d=draft; m=resolve(p)
    before=Marshal.dump([p,d,m]); SERVICE.attach(draft:d,plan:p,match:m)
    assert_equal before,Marshal.dump([p,d,m])
  end
  test 'rejects forged authorization' do
    p=plan; m=resolve(p).merge('execution_authorized'=>true)
    assert_raises(SERVICE::Rejected){SERVICE.attach(draft:draft,plan:p,match:m)}
  end
  test 'rejects mismatched ticket and requirement' do
    p=plan; d=draft; d['ticket_id']=47
    assert_raises(SERVICE::Rejected){SERVICE.attach(draft:d,plan:p,match:resolve(p))}
    assert_raises(SERVICE::Rejected){SERVICE.attach(draft:draft,plan:p,match:resolve(p).merge('required_capability'=>'other'))}
  end
  test 'rejects unsafe draft and missing engineering evidence' do
    p=plan; d=draft; d['gatekeeper_approved']=true
    assert_raises(SERVICE::Rejected){SERVICE.attach(draft:d,plan:p,match:resolve(p))}
    d=draft; d.delete('studio_capability_engineering_plan')
    assert_raises(SERVICE::Rejected){SERVICE.attach(draft:d,plan:p,match:resolve(p))}
  end
end
