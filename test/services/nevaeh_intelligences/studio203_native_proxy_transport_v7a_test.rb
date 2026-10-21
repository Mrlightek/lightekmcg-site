# frozen_string_literal: true
require 'test_helper'
class Studio203NativeProxyTransportV7aTest < ActiveSupport::TestCase
  Bridge = NevaehIntelligences::Studio203ProsePolicyBridgeV7a

  def native_ticket(fields = {})
    ticket = Marlon::Ticket.allocate
    ticket.define_singleton_method(:id) { 83921 }
    ticket.define_singleton_method(:persisted?) { true }
    ticket.define_singleton_method(:extra_fields) { fields }
    ticket
  end

  def test_native_transport_delegates_to_original_persisted_ticket
    fields = {'project_tracking' => {'key' => 'STUDIO-203'}, 'nevaeh_work_order' => {'work_type' => 'build'}}
    original = native_ticket(fields)
    proxy = Bridge::TicketProxy.new(original, fields.merge('studio203_acceptance' => {'schema_version' => 1}))
    assert_same original, Bridge::NativeTicketTransport.unwrap(proxy)
    planner = Object.new
    planner.define_singleton_method(:from_ticket) { |ticket:| ticket }
    reader = Object.new
    reader.define_singleton_method(:read!) { |ticket:| ticket }
    assert_same original, Bridge::NativePlannerTransport.new(planner).from_ticket(ticket: proxy)
    assert_same original, Bridge::NativeWorkOrderTransport.new(reader).read!(ticket: proxy)
  end

  def test_identity_or_reserved_field_tampering_is_rejected
    original = native_ticket({'project_tracking' => {'key' => 'STUDIO-203'}, 'nevaeh_work_order' => {'work_type' => 'build'}})
    proxy = Bridge::TicketProxy.new(original, original.extra_fields.merge('nevaeh_work_order' => {'work_type' => 'deploy'}, 'studio203_acceptance' => {}))
    assert_raises(Bridge::ReviewRequired) { Bridge::NativeTicketTransport.unwrap(proxy) }
    altered = Bridge::TicketProxy.new(original, original.extra_fields.merge('studio203_acceptance' => {}))
    altered.instance_variable_set(:@id, -1)
    assert_raises(Bridge::ReviewRequired) { Bridge::NativeTicketTransport.unwrap(altered) }
  end

  def test_original_ticket_must_be_persisted
    original = native_ticket
    original.define_singleton_method(:persisted?) { false }
    proxy = Bridge::TicketProxy.new(original, original.extra_fields.merge('studio203_acceptance' => {}))
    assert_raises(Bridge::ReviewRequired) { Bridge::NativeTicketTransport.unwrap(proxy) }
  end
end
