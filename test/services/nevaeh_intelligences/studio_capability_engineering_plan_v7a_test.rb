# frozen_string_literal: true
require 'test_helper'

class StudioCapabilityEngineeringPlanV7aTest < ActiveSupport::TestCase
  BRIDGE = NevaehIntelligences::StudioCapabilityEngineeringPlanV7a

  class Planner
    class << self
      attr_accessor :last_ticket, :result
      def from_ticket(ticket:)
        self.last_ticket = ticket
        result
      end
    end
  end

  def safe_plan
    {
      'required_capability' => 'capability.build',
      'capability_resolution' => 'unverified_requires_repository_and_registry_inspection',
      'execution_enabled' => false,
      'gatekeeper' => {
        'authorization_required' => true,
        'production_execution_allowed' => false,
        'human_release_approval_required' => true
      }
    }
  end

  setup { Planner.result = safe_plan; Planner.last_ticket = nil }

  test 'calls existing planner and attaches evidence without mutating it' do
    ticket = Object.new
    result = BRIDGE.from_ticket(ticket: ticket, capability_snapshot: [{ 'slug' => 'capability.build', 'enabled' => true }], planner: Planner)
    assert_same ticket, Planner.last_ticket
    assert_equal 'discovered_unverified', result.dig('studio203_evidence', 'discovery_status')
    assert_equal false, result.dig('studio203_evidence', 'execution_authorized')
    assert_equal false, result.dig('studio203_evidence', 'release_approved')
    assert_equal false, result['execution_enabled']
    assert_nil Planner.result['studio203_evidence']
  end

  test 'unknown capabilities remain non executable' do
    result = BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: [], planner: Planner)
    assert_equal 'not_found', result.dig('studio203_evidence', 'discovery_status')
    assert_equal false, result.dig('studio203_evidence', 'execution_authorized')
  end

  test 'rejects duplicate identifiers without authorizing' do
    assert_raises(BRIDGE::Rejected) do
      BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: [{ 'key' => 'capability.build' }, { 'slug' => 'capability.build' }], planner: Planner)
    end
  end

  test 'rejects unsafe planning policy' do
    %w[execution_enabled authorization_required production_execution_allowed human_release_approval_required].each do |field|
      plan = safe_plan
      if field == 'execution_enabled'
        plan[field] = true
      else
        plan['gatekeeper'][field] = (field == 'production_execution_allowed')
      end
      Planner.result = plan
      assert_raises(BRIDGE::Rejected, field) { BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: [], planner: Planner) }
    end
  end

  test 'rejects previously resolved planning and invalid planner output' do
    Planner.result = safe_plan.merge('capability_resolution' => 'authorized')
    assert_raises(BRIDGE::Rejected) { BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: [], planner: Planner) }
    Planner.result = nil
    assert_raises(BRIDGE::Rejected) { BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: [], planner: Planner) }
  end

  test 'deterministic output regardless of discovery order' do
    a = [{ 'slug' => 'capability.build' }, { 'slug' => 'other.capability' }]
    b = a.reverse
    assert_equal BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: a, planner: Planner),
                 BRIDGE.from_ticket(ticket: Object.new, capability_snapshot: b, planner: Planner)
  end

  test 'real planner interface remains available' do
    assert_respond_to NevaehIntelligences::GithubDevelopmentPlanV7a, :from_ticket
    assert_equal [[:keyreq, :ticket]], NevaehIntelligences::GithubDevelopmentPlanV7a.method(:from_ticket).parameters
  end
end
