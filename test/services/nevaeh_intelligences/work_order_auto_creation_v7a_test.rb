# frozen_string_literal: true
require 'test_helper'
class WorkOrderAutoCreationV7aTest < ActiveSupport::TestCase
  Ticket = Struct.new(:id)
  class FakeAdapter
    attr_reader :attach_count, :dispatch_count
    def initialize(existing: nil, valid: true)
      @existing, @valid = existing, valid
      @attach_count = @dispatch_count = 0
    end
    def read(ticket:); @existing; end
    def validate(ticket:, order:); @valid && order.is_a?(Hash); end
    def template(ticket:); { 'ticket_id' => ticket.id, 'gatekeeper_approved' => true, 'execution_enabled' => true }; end
    def attach(ticket:, order:, previous:)
      @attach_count += 1
      @existing = order
    end
    def dispatch!(**); @dispatch_count += 1; raise 'dispatch forbidden'; end
  end
  def service; NevaehIntelligences::WorkOrderAutoCreationV7a; end
  test 'missing work order creates inert review-required order' do
    adapter = FakeAdapter.new
    result = service.ensure_for_ticket!(ticket: Ticket.new(14), adapter: adapter)
    assert_equal 'created_review_required', result.fetch('state')
    assert_equal 'review_required', result.fetch('work_order').fetch('status')
    %w[gatekeeper_approved execution_enabled production_allowed release_approved].each { |key| assert_equal false, result.fetch('work_order').fetch(key) }
    assert_equal 1, adapter.attach_count
    assert_equal 0, adapter.dispatch_count
  end
  test 'repeated ticket does not create duplicate' do
    adapter = FakeAdapter.new
    service.ensure_for_ticket!(ticket: Ticket.new(14), adapter: adapter)
    result = service.ensure_for_ticket!(ticket: Ticket.new(14), adapter: adapter)
    assert_equal 'existing_valid', result.fetch('state')
    assert_equal 1, adapter.attach_count
  end
  test 'invalid existing document fails closed when a valid replacement cannot be verified' do
    adapter = FakeAdapter.new(existing: { 'status' => 'corrupted' }, valid: false)
    assert_raises(service::Rejected) { service.ensure_for_ticket!(ticket: Ticket.new(14), adapter: adapter) }
    assert_equal 0, adapter.attach_count
    assert_equal 0, adapter.dispatch_count
  end
  test 'missing ticket rejects without writes' do
    adapter = FakeAdapter.new
    assert_raises(service::Rejected) { service.ensure_for_ticket!(ticket: nil, adapter: adapter) }
    assert_equal 0, adapter.attach_count
  end
end
