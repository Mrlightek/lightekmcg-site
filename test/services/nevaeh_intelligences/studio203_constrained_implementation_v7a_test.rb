# frozen_string_literal: true
require 'test_helper'
require 'tmpdir'
require 'json'

class Studio203ConstrainedImplementationV7aTest < ActiveSupport::TestCase
  Engine = NevaehIntelligences::Studio203ConstrainedImplementationV7a
  Ticket = Struct.new(:id) { def persisted? = true }
  class Planner
    def self.from_ticket(ticket:)
      {'ticket_id' => ticket.id, 'tracking_key' => 'STUDIO-203', 'status' => 'planning_only',
       'execution_enabled' => false, 'gatekeeper' => {'production_execution_allowed' => false,
       'human_release_approval_required' => true}, 'fingerprint' => 'a' * 64}
    end
  end
  class UnsafePlanner
    def self.from_ticket(ticket:)
      Planner.from_ticket(ticket: ticket).merge('execution_enabled' => true)
    end
  end
  def test_preview_is_inert_and_provenanced
    out = Engine.preview(ticket: Ticket.new(123), planner: Planner)
    assert_equal 'STUDIO-203', out.fetch('tracking_key')
    assert_equal false, out.fetch('authorization_granted')
    assert_equal false, out.fetch('implementation_verified')
    assert_equal 'fixed_allowlisted_template', out.fetch('code_authoring_mode')
    assert_match(/\A[0-9a-f]{64}\z/, out.fetch('source_sha256'))
  end
  def test_rejects_executable_plan
    assert_raises(Engine::Rejected) { Engine.preview(ticket: Ticket.new(123), planner: UnsafePlanner) }
  end
  def test_refuses_destination_collision
    Dir.mktmpdir('studio203-t20-test-') do |d|
      assert_raises(Engine::Rejected) { Engine.generate(ticket: Ticket.new(123), destination: d, planner: Planner) }
    end
  end
  def test_writes_candidate_patch_and_provenance_outside_checkout
    Dir.mktmpdir('studio203-t20-test-') do |dir|
      dest = File.join(dir, 'generated')
      out = Engine.generate(ticket: Ticket.new(123), destination: dest, planner: Planner)
      assert_equal false, out.fetch('is_autonomous_reasoning')
      assert_equal false, out.fetch('tests_executed')
      source = File.read(File.join(dest, 'ticket_snapshot_contract.rb'))
      assert_match(/TicketSnapshotContract/, source)
      assert_equal Digest::SHA256.hexdigest(source), out.fetch('source_sha256')
      assert_match(/\+module Studio/, File.read(File.join(dest, 'review.patch')))
      assert_equal 'STUDIO-203', JSON.parse(File.read(File.join(dest, 'provenance.json'))).fetch('tracking_key')
    end
  end
  def test_refuses_in_checkout_destination
    assert_raises(Engine::Rejected) do
      Engine.generate(ticket: Ticket.new(123), destination: Rails.root.join('tmp/studio203-t20-unsafe').to_s, planner: Planner)
    end
  end
end
