# frozen_string_literal: true
require 'test_helper'

class StudioCapabilityDraftEvidenceV7aTest < ActiveSupport::TestCase
  def plan
    {'ticket_id'=>46, 'tracking_key'=>'STUDIO-203', 'fingerprint'=>'sha',
     'status'=>'planning_only', 'execution_enabled'=>false,
     'gatekeeper'=>{'production_execution_allowed'=>false}}
  end
  def draft
    {'ticket_id'=>46, 'tracking_key'=>'STUDIO-203', 'development_plan_fingerprint'=>'sha',
     'status'=>'review_only', 'gatekeeper_approved'=>false, 'executable'=>false,
     'production_allowed'=>false}
  end
  def compose(d=draft, p=plan, e=plan)
    NevaehIntelligences::StudioCapabilityDraftEvidenceV7a.attach(draft:d, original_plan:p, enriched_plan:e)
  end
  test 'attaches evidence without granting execution' do
    result=compose
    assert_equal false, result.fetch('gatekeeper_approved')
    assert_equal false, result.fetch('executable')
    assert_equal false, result.fetch('production_allowed')
    assert_equal 'STUDIO-203', result.fetch('studio_capability_engineering_plan').fetch('tracking_key')
  end
  test 'does not mutate input data' do
    d=draft; p=plan; e=plan; before=Marshal.dump([d,p,e]); compose(d,p,e)
    assert_equal before, Marshal.dump([d,p,e])
  end
  test 'rejects mismatched ticket' do
    e=plan; e['ticket_id']=99
    assert_raises(NevaehIntelligences::StudioCapabilityDraftEvidenceV7a::Rejected){compose(draft,plan,e)}
  end
  test 'rejects executable enriched plan' do
    e=plan; e['execution_enabled']=true
    assert_raises(NevaehIntelligences::StudioCapabilityDraftEvidenceV7a::Rejected){compose(draft,plan,e)}
  end
  test 'rejects draft approval flags' do
    d=draft; d['gatekeeper_approved']=true
    assert_raises(NevaehIntelligences::StudioCapabilityDraftEvidenceV7a::Rejected){compose(d)}
  end
  test 'rejects false plan fingerprints' do
    d=draft; d['development_plan_fingerprint']='bad'
    assert_raises(NevaehIntelligences::StudioCapabilityDraftEvidenceV7a::Rejected){compose(d)}
  end
end
