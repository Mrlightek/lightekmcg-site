# frozen_string_literal: true
require "test_helper"

class NevaehTicketSubjectBindingV2fTest < ActiveSupport::TestCase
  FakeScope = Struct.new(:record) do
    def includes(_association) = self
    def find_by(intent_key:)
      intent_key == "studio.project.create" ? record : nil
    end
  end
  FakeRecord = Struct.new(:nevaeh_capability, :dispatch_action, :intent_key, :id, :target_model, :operation, :execution_mode)
  FakeCapability = Struct.new(:event_types, :slug)

  def with_singleton_stub(receiver, method_name, implementation)
    singleton = receiver.singleton_class
    original = receiver.method(method_name)
    singleton.define_method(method_name, &implementation)
    yield
  ensure
    singleton.define_method(method_name, original) if original
  end

  test "ticket reaches Nevaeh handle as the persisted subject" do
    ticket = Marlon::Ticket.create!(title: "Subject handoff", category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open")
    cap = FakeCapability.new(["studio.project.create.requested"], "studio.project.create")
    record = FakeRecord.new(cap, "create", "studio.project.create", 123, "StudioProject", "create", "async")
    captured = nil
    fake_handle = lambda do |**kwargs|
      captured = kwargs
      Struct.new(:work_item).new(Struct.new(:id).new(732001))
    end
    with_singleton_stub(NevaehIntelligence, :available, -> { FakeScope.new(record) }) do
      with_singleton_stub(Nevaeh, :handle, fake_handle) do
        result = NevaehIntelligences::Dispatch.call(intent_key: "studio.project.create",
          actor: Object.new, ticket: ticket, execute: true, payload: {name: "Handoff"}, correlation_id: "v2f-subject")
        assert_equal 732001, result.fetch("work_item_id")
      end
    end
    assert_same ticket, captured.fetch(:subject)
    assert_equal "v2f-subject", captured.fetch(:correlation_id)
    assert_equal "studio.project.create", captured.fetch(:capability_hint)
  end

  test "unpersisted ticket cannot be forwarded as a subject" do
    cap = FakeCapability.new(["studio.project.create.requested"], "studio.project.create")
    record = FakeRecord.new(cap, "create", "studio.project.create", 123, "StudioProject", "create", "async")
    with_singleton_stub(NevaehIntelligence, :available, -> { FakeScope.new(record) }) do
      error = assert_raises(NevaehIntelligences::Dispatch::Unavailable) do
        NevaehIntelligences::Dispatch.call(intent_key: "studio.project.create", actor: Object.new,
          ticket: Marlon::Ticket.new, execute: true, payload: {name: "Handoff"})
      end
      assert_match(/Persisted Marlon ticket/, error.message)
    end
  end
end
