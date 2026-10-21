# frozen_string_literal: true
require 'test_helper'

class ReconcileLinkedEvidenceV2fTest < ActiveSupport::TestCase
  class FakeTicket
    attr_reader :id, :extra_fields, :audit
    def initialize(id, linked)
      @id = id
      @extra_fields = {'nevaeh' => {'reservation_id' => 'reservation-one', 'work_item_id' => linked, 'execution_status' => 'dispatched'}}
      @audit = []
    end
    def log!(**attributes)
      @audit << attributes
    end
  end

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

  def with_services(ticket, classification:, ids:)
    calls = {evidence: 0, reconcile: 0}
    expected_ticket = ticket
    swap_singleton(Marlon::Ticket, :find, ->(id) { raise 'wrong ticket' unless id == ticket.id; ticket }) do
      swap_singleton(NevaehIntelligences::RecoveryEvidenceV2f, :for_ticket, ->(arg) {
        raise 'wrong subject' unless arg.equal?(ticket)
        calls[:evidence] += 1
        {'classification' => classification, 'reservation_id' => 'reservation-one', 'work_item_ids' => ids, 'automatic_retry_allowed' => false}
      }) do
        swap_singleton(NevaehIntelligences::TicketExecution, :reconcile!, ->(ticket:) {
          calls[:reconcile] += 1
          raise 'wrong ticket at reconciliation' unless ticket.equal?(expected_ticket)
          'resolved'
        }) do
          yield calls
        end
      end
    end
  end

  test 'linked receipt with duplicate work items stops verification and writes durable review event' do
    ticket = FakeTicket.new(53101, 500)
    with_services(ticket, classification: 'duplicate_work_items', ids: [500, 501]) do |calls|
      assert_equal 'manual_review', NevaehIntelligences::ReconcileTicketJob.new.perform(ticket.id)
      assert_equal 0, calls[:reconcile]
      assert_equal 1, calls[:evidence]
    end
    assert_equal 'nevaeh_recovery_manual_review', ticket.audit.first.fetch(:action)
    assert_equal [500, 501], JSON.parse(ticket.audit.first.fetch(:detail)).fetch('work_item_ids')
    assert_equal 'dispatched', ticket.extra_fields.dig('nevaeh', 'execution_status')
  end

  test 'linked receipt with mismatched work item stops verification' do
    ticket = FakeTicket.new(53102, 999)
    with_services(ticket, classification: 'linked_item_mismatch', ids: [500]) do |calls|
      assert_equal 'manual_review', NevaehIntelligences::ReconcileTicketJob.new.perform(ticket.id)
      assert_equal 0, calls[:reconcile]
    end
    assert_equal 'linked_item_mismatch', JSON.parse(ticket.audit.first.fetch(:detail)).fetch('classification')
  end

  test 'single matching work item keeps existing reconciliation path' do
    ticket = FakeTicket.new(53103, 500)
    with_services(ticket, classification: 'queued', ids: [500]) do |calls|
      assert_equal 'resolved', NevaehIntelligences::ReconcileTicketJob.new.perform(ticket.id)
      assert_equal 1, calls[:reconcile]
      assert_equal 1, calls[:evidence]
    end
    assert_empty ticket.audit
  end
end
