# frozen_string_literal: true
require 'test_helper'
require 'tmpdir'
require 'json'
require 'digest'

class Studio203RepositoryAwareAuthoringV7aTest < ActiveSupport::TestCase
  Engine = NevaehIntelligences::Studio203RepositoryAwareAuthoringV7a
  Ticket = Struct.new(:id) { def persisted? = true }
  class Planner
    def self.from_ticket(ticket:)
      {'ticket_id' => ticket.id, 'tracking_key' => 'STUDIO-203', 'status' => 'planning_only',
       'execution_enabled' => false, 'gatekeeper' => {'production_execution_allowed' => false,
       'human_release_approval_required' => true}, 'fingerprint' => 'a' * 64}
    end
  end
  RULES = {'require_published' => true, 'include_disabled' => false}.freeze
  def test_generates_two_behaviorally_distinct_sources
    a = Engine.synthesize(Engine.normalize_changes(RULES))
    b = Engine.synthesize(Engine.normalize_changes({'require_published' => false, 'include_disabled' => true}))
    refute_equal a, b
    assert Ripper.sexp(a)
    assert Ripper.sexp(b)
    assert_includes a, "next unless row['published'] == true"
    refute_includes b, "next unless row['published'] == true"
  end
  def test_rejects_unknown_spec_and_nonboolean_values
    assert_raises(Engine::Rejected) { Engine.normalize_changes({'require_published' => true, 'include_disabled' => false, 'eval' => true}) }
    assert_raises(Engine::Rejected) { Engine.normalize_changes({'require_published' => true, 'include_disabled' => 'yes'}) }
  end
  def test_inert_preview_is_bound_to_real_sources
    result = Engine.preview(ticket: Ticket.new(9), changes: RULES, planner: Planner)
    assert_equal 'bounded_rule_composition', result.fetch('code_authoring_mode')
    assert_equal false, result.fetch('execution_authorized')
    assert_equal false, result.fetch('autonomous_ai_authoring')
    assert_equal 2, result.fetch('reference_sha256').length
  end
  def test_generates_review_artifacts_and_verifies_behavior
    Dir.mktmpdir('studio203-t22-') do |dir|
      dest = File.join(dir, 'candidate')
      result = Engine.generate(ticket: Ticket.new(9), changes: RULES, destination: dest, planner: Planner)
      path = File.join(dest, 'ticket_snapshot_filter.rb')
      assert_equal Digest::SHA256.file(path).hexdigest, result.fetch('source_sha256')
      require path
      mod = Studio::Capabilities::TicketSnapshotFilter
      rows = [{'key' => 'alpha', 'published' => true, 'enabled' => true},
              {'key' => 'beta', 'published' => false, 'enabled' => true},
              {'key' => 'gamma', 'published' => true, 'enabled' => false}]
      assert_equal ['alpha'], mod.call(entries: rows).map { |r| r.fetch('key') }
      assert_equal false, mod.call(entries: rows).first.fetch('execution_authorized')
      assert_raises(mod::Invalid) { mod.call(entries: [rows.first, rows.first]) }
      assert File.file?(File.join(dest, 'review.patch'))
      assert_equal 'STUDIO-203', JSON.parse(File.read(File.join(dest, 'provenance.json'))).fetch('tracking_key')
    end
  end
  def test_rejects_collision_and_in_repository_output
    Dir.mktmpdir('studio203-t22-') do |dir|
      assert_raises(Engine::Rejected) { Engine.generate(ticket: Ticket.new(9), changes: RULES, destination: dir, planner: Planner) }
    end
    assert_raises(Engine::Rejected) { Engine.generate(ticket: Ticket.new(9), changes: RULES, destination: Rails.root.join('tmp/t22-candidate').to_s, planner: Planner) }
  end
end
