# frozen_string_literal: true
require 'test_helper'
require 'digest'
require 'json'
require 'tmpdir'

class Studio203ProsePolicyBridgeV7aTest < ActiveSupport::TestCase
  Engine = NevaehIntelligences::Studio203ProsePolicyBridgeV7a
  Ticket = Struct.new(:id, :extra_fields) { def persisted? = true }
  class Planner
    def self.from_ticket(ticket:)
      {'ticket_id' => ticket.id, 'tracking_key' => 'STUDIO-203', 'status' => 'planning_only',
       'execution_enabled' => false, 'gatekeeper' => {'production_execution_allowed' => false,
       'human_release_approval_required' => true}, 'fingerprint' => 'a' * 64}
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
  class FakeKbProof
    def self.verify(ticket:, structured:, acceptance_sha256:)
      {'verified' => true, 'status' => 'allow_review_only', 'ticket_id' => ticket.id,
       'tracking_key' => 'STUDIO-203', 'acceptance_sha256' => acceptance_sha256,
       'policy_id' => 'test-fixture-only', 'policy_sha256' => 'f' * 64,
       'execution_authorized' => false, 'human_review_required' => true}
    end
  end
  def ticket(sentences = ['Include only published capabilities.', 'Exclude disabled capabilities.'])
    Ticket.new(71, {'project_tracking' => {'key' => 'STUDIO-203'},
                    'studio203_plain_english_acceptance' => sentences})
  end
  def test_exact_prose_derives_both_rule_values
    assert_equal({'schema_version' => 1, 'requirements' => [{'rule' => 'require_published', 'value' => true}, {'rule' => 'include_disabled', 'value' => false}]}, Engine.interpret(ticket: ticket))
    other = Engine.interpret(ticket: ticket(['Include published and unpublished capabilities.', 'Include disabled capabilities.']))
    assert_equal false, other.fetch('requirements')[0].fetch('value')
    assert_equal true, other.fetch('requirements')[1].fetch('value')
  end
  def test_unknown_and_conflicting_prose_denied
    assert_raises(Engine::ReviewRequired) { Engine.interpret(ticket: ticket(['Publish everything automatically', 'Exclude disabled capabilities'])) }
    assert_raises(Engine::ReviewRequired) { Engine.interpret(ticket: ticket(['Include only published capabilities', 'Include published and unpublished capabilities'])) }
  end
  def test_real_kb_is_denied_by_default
    e = assert_raises(Engine::ReviewRequired) { Engine.preview(ticket: ticket, planner: Planner, work_order_reader: WorkReader) }
    assert_match(/KB policy verification unavailable/, e.message)
  end
  def test_test_fixture_proof_enables_review_only_preview
    result = Engine.preview(ticket: ticket, kb_adapter: FakeKbProof, planner: Planner, work_order_reader: WorkReader)
    assert_equal true, result.fetch('kb_policy_verified')
    assert_equal false, result.fetch('execution_authorized')
    assert_equal true, result.fetch('requires_human_review')
    assert_equal 'test-fixture-only', result.fetch('policy_id')
    assert_equal 'closed_vocabulary_exact_sentences', result.fetch('interpretation_mode')
  end
  def test_policy_evidence_mismatch_rejected
    bad = Class.new do
      def self.verify(ticket:, structured:, acceptance_sha256:)
        {'verified' => true, 'status' => 'allow_review_only', 'ticket_id' => ticket.id,
         'tracking_key' => 'STUDIO-203', 'acceptance_sha256' => '0' * 64,
         'policy_id' => 'bad', 'policy_sha256' => 'f' * 64,
         'execution_authorized' => false, 'human_review_required' => true}
      end
    end
    assert_raises(Engine::ReviewRequired) { Engine.evaluate(ticket: ticket, kb_adapter: bad) }
  end
  def test_review_only_generation_with_fixture_policy
    Dir.mktmpdir('studio203-t24-') do |dir|
      out = Engine.generate(ticket: ticket, destination: File.join(dir, 'candidate'),
         kb_adapter: FakeKbProof, planner: Planner, work_order_reader: WorkReader)
      assert_equal false, out.fetch('execution_authorized')
      assert_equal true, out.fetch('generated_artifacts_review_only')
      assert File.file?(File.join(dir, 'candidate', 'review.patch'))
    end
  end
end
