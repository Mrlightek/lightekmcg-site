# frozen_string_literal: true
require 'test_helper'
class WorkOrderNativeAdapterV7aTest < ActiveSupport::TestCase
  Adapter = NevaehIntelligences::WorkOrderNativeAdapterV7a
  def new_ticket
    # No database records: fake implements only persisted ticket storage boundary.
    Class.new do
      attr_accessor :status, :extra_fields
      attr_reader :logs
      def initialize
        @status = 'open'
        @extra_fields = {}
        @logs = []
      end
      def persisted? = true
      def with_lock = yield
      def update!(extra_fields:) = (@extra_fields = extra_fields)
      def log!(action:, detail:) = @logs << [action, detail]
    end.new
  end
  def call(ticket)
    Adapter.ensure_for_ticket!(ticket: ticket, objective: 'Produce review-only Studio capability evidence', acceptance_criteria: ['Candidate is verifiable'])
  end
  test 'creates and reuses native validated work order without dispatch' do
    t = new_ticket
    one = call(t)
    assert_equal 'created', one.fetch('state')
    assert_equal false, one.fetch('dispatch_performed')
    assert_equal false, one.fetch('authorization_granted')
    assert_equal 'build', NevaehIntelligences::WorkOrder.read!(ticket: t).fetch('work_type')
    assert_equal 'reused', call(t).fetch('state')
    assert_equal 1, t.logs.size
  end
  test 'preserves malformed prior order before native replacement' do
    t = new_ticket
    t.extra_fields = { 'nevaeh_work_order' => { 'old' => 'invalid' }, 'other' => 'preserve' }
    result = call(t)
    assert_equal 'repaired', result.fetch('state')
    assert_equal 'preserve', t.extra_fields.fetch('other')
    assert_equal({ 'old' => 'invalid' }, t.extra_fields.fetch(Adapter::HISTORY_KEY).first.fetch('previous_order'))
    assert_equal 'build', NevaehIntelligences::WorkOrder.read!(ticket: t).fetch('work_type')
  end
  test 'rejects reserved ticket without changes' do
    t = new_ticket
    t.extra_fields = { 'nevaeh' => { 'work_item_id' => 'already-reserved' } }
    before = Marshal.dump(t.extra_fields)
    assert_raises(Adapter::Rejected) { call(t) }
    assert_equal before, Marshal.dump(t.extra_fields)
  end
  test 'rejects resolved ticket' do
    t = new_ticket
    t.status = 'resolved'
    assert_raises(Adapter::Rejected) { call(t) }
  end
  test 'rejects malformed criteria without changes' do
    t = new_ticket
    assert_raises(Adapter::Rejected) { Adapter.ensure_for_ticket!(ticket: t, objective: 'x', acceptance_criteria: []) }
    assert_empty t.extra_fields
  end
end
