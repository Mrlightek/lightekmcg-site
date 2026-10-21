# frozen_string_literal: true
require 'test_helper'
require 'tmpdir'
require 'json'
require 'digest'

class Studio203TicketDecisionBridgeV7aTest < ActiveSupport::TestCase
  Engine = NevaehIntelligences::Studio203TicketDecisionBridgeV7a
  Ticket = Struct.new(:id, :extra_fields) { def persisted? = true }
  class Planner
    def self.from_ticket(ticket:)
      { 'ticket_id' => ticket.id, 'tracking_key' => 'STUDIO-203',
        'status' => 'planning_only', 'execution_enabled' => false,
        'gatekeeper' => {'production_execution_allowed' => false,
                         'human_release_approval_required' => true},
        'fingerprint' => 'a' * 64 }
    end
  end
  class WorkReader
    def self.read!(ticket:)
      {'work_type' => 'build', 'intent_key' => 'github:Mrlightek/lightekmcg-site:STUDIO-203',
       'execution_policy' => {'environment' => 'test', 'approval' => 'gatekeeper',
         'execution_enabled' => false, 'production_allowed' => false,
         'requires_human_release_approval' => true}}
    end
  end
  def fixture(requirements = [{'rule' => 'require_published', 'value' => true}, {'rule' => 'include_disabled', 'value' => false}])
    Ticket.new(71, {'project_tracking' => {'key' => 'STUDIO-203'},
      'studio203_acceptance' => {'schema_version' => 1, 'requirements' => requirements}})
  end
  def test_derives_ticket_rules_not_caller_specification
    assert_equal({'require_published' => true, 'include_disabled' => false}, Engine.decisions(ticket: fixture, work_order_reader: WorkReader))
    other = fixture([{'rule' => 'require_published', 'value' => false}, {'rule' => 'include_disabled', 'value' => true}])
    assert_equal({'require_published' => false, 'include_disabled' => true}, Engine.decisions(ticket: other, work_order_reader: WorkReader))
  end
  def test_rejects_unsupported_and_incomplete_rules
    bad = fixture([{'rule' => 'require_published', 'value' => true}, {'rule' => 'execute_jobs', 'value' => true}])
    assert_raises(Engine::Rejected) { Engine.decisions(ticket: bad, work_order_reader: WorkReader) }
    short = fixture([{'rule' => 'require_published', 'value' => true}])
    assert_raises(Engine::Rejected) { Engine.decisions(ticket: short, work_order_reader: WorkReader) }
  end
  def test_rejects_duplicate_and_nonboolean_rules
    duplicate = fixture([{'rule' => 'require_published', 'value' => true}, {'rule' => 'require_published', 'value' => false}])
    assert_raises(Engine::Rejected) { Engine.decisions(ticket: duplicate, work_order_reader: WorkReader) }
    invalid = fixture([{'rule' => 'require_published', 'value' => 'true'}, {'rule' => 'include_disabled', 'value' => false}])
    assert_raises(Engine::Rejected) { Engine.decisions(ticket: invalid, work_order_reader: WorkReader) }
  end
  def test_rejects_missing_work_order_and_wrong_ticket
    assert_raises(Engine::Rejected) { Engine.decisions(ticket: Ticket.new(1, {'project_tracking' => {'key' => 'wrong'}}), work_order_reader: WorkReader) }
    reader = Class.new do
      def self.read!(ticket:)
        raise NevaehIntelligences::WorkOrder::Invalid, 'missing work order'
      end
    end
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { Engine.decisions(ticket: fixture, work_order_reader: reader) }
  end
  def test_preview_links_ticket_decisions_to_repository_evidence
    out = Engine.preview(ticket: fixture, planner: Planner, work_order_reader: WorkReader)
    assert_equal true, out.fetch('ticket_derived_decisions')
    assert_equal 'structured_ticket_acceptance_only', out.fetch('decision_origin')
    assert_equal false, out.fetch('kb_policy_verified')
    assert_equal false, out.fetch('autonomous_ai_authoring')
    assert_equal 2, out.fetch('reference_sha256').length
  end
  def test_generate_distinct_code_and_review_patch
    Dir.mktmpdir('studio203-t23-') do |dir|
      a = Engine.generate(ticket: fixture, destination: File.join(dir, 'a'), planner: Planner, work_order_reader: WorkReader)
      b = Engine.generate(ticket: fixture([{'rule' => 'require_published', 'value' => false}, {'rule' => 'include_disabled', 'value' => true}]), destination: File.join(dir, 'b'), planner: Planner, work_order_reader: WorkReader)
      refute_equal a.fetch('source_sha256'), b.fetch('source_sha256')
      assert File.file?(File.join(dir, 'a', 'review.patch'))
      assert File.file?(File.join(dir, 'b', 'provenance.json'))
      assert_equal false, a.fetch('kb_policy_verified')
      assert_equal true, b.fetch('requires_human_review')
    end
  end
  def test_rejects_generation_inside_checkout
    assert_raises(NevaehIntelligences::Studio203RepositoryAwareAuthoringV7a::Rejected) do
      Engine.generate(ticket: fixture, destination: Rails.root.join('tmp/t23-generated').to_s, planner: Planner, work_order_reader: WorkReader)
    end
  end
end
