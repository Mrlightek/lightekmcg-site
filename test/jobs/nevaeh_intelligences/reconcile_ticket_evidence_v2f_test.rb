# frozen_string_literal: true
require 'test_helper'

class ReconcileTicketEvidenceV2fTest < ActiveSupport::TestCase
  FakeTicket = Struct.new(:id, :extra_fields)

  def swap_singleton(owner, name, replacement)
    singleton = owner.singleton_class
    local = singleton.instance_methods(false).include?(name)
    original = owner.method(name) if owner.respond_to?(name)
    singleton.send(:define_method, name, &replacement)
    yield
  ensure
    if local && original
      singleton.send(:define_method, name, original)
    elsif singleton && singleton.instance_methods(false).include?(name)
      singleton.send(:remove_method, name)
    end
  end

  test 'unlinked uncertain dispatch is classified and held for manual review' do
    ticket = FakeTicket.new(9201, {'nevaeh' => {'reservation_id' => 'reservation', 'execution_status' => 'dispatch_uncertain'}})
    count = 0
    swap_singleton(Marlon::Ticket, :find, ->(_id) { ticket }) do
      swap_singleton(NevaehIntelligences::RecoveryEvidenceV2f, :for_ticket, ->(arg) {
        raise "unexpected ticket passed to recovery evidence" unless arg.equal?(ticket)
        count += 1
        {'classification' => 'no_matching_work_item', 'work_item_ids' => []}
      }) do
        swap_singleton(NevaehIntelligences::TicketExecution, :reconcile!, ->(**) { raise('must not reconcile unknown item') }) do
          assert_equal 'manual_review', NevaehIntelligences::ReconcileTicketJob.new.perform(ticket.id)
        end
      end
    end
    assert_equal 1, count
    assert_nil ticket.extra_fields.dig('nevaeh', 'work_item_id')
    assert_equal 'dispatch_uncertain', ticket.extra_fields.dig('nevaeh', 'execution_status')
  end

  test 'discovered completed item is not silently linked and not retried' do
    ticket = FakeTicket.new(9202, {'nevaeh' => {'reservation_id' => 'reservation', 'execution_status' => 'dispatch_uncertain'}})
    swap_singleton(Marlon::Ticket, :find, ->(_id) { ticket }) do
      swap_singleton(NevaehIntelligences::RecoveryEvidenceV2f, :for_ticket, ->(_) {
        {'classification' => 'completed_unverified', 'work_item_ids' => [888]}
      }) do
        assert_equal 'manual_review', NevaehIntelligences::ReconcileTicketJob.new.perform(ticket.id)
      end
    end
    assert_nil ticket.extra_fields.dig('nevaeh', 'work_item_id')
  end
end
