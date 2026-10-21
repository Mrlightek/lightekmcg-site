# frozen_string_literal: true
require "test_helper"

class NevaehTicketEvidenceTest < ActiveSupport::TestCase
  FakeItem = Struct.new(:id, :kind, :correlation_id, :status, keyword_init: true)

  def ticket(data)
    Marlon::Ticket.new(extra_fields: data)
  end

  test "ordinary ticket has no Nevaeh dashboard" do
    evidence = NevaehIntelligences::TicketEvidence.new(ticket({"notes" => "plain"}))
    assert_not evidence.present?
    assert_equal "not dispatched", evidence.work_item_status
  end

  test "saved assignment is visible without triggering execution" do
    order = {"version" => 1, "work_type" => "create", "intent_key" => "studio.project.create", "objective" => "Create project"}
    evidence = NevaehIntelligences::TicketEvidence.new(ticket({"nevaeh_work_order" => order}))
    assert evidence.present?
    assert_equal "Create project", evidence.work_order["objective"]
    assert_equal "not dispatched", evidence.work_item_status
  end

  test "failed execution exposes persisted error and verification" do
    evidence = NevaehIntelligences::TicketEvidence.new(ticket({"nevaeh" => {"execution_status" => "verification_failed", "error" => "bad result", "verification" => {"result" => {"project_id" => 4}}}}))
    assert evidence.present?
    assert_equal "bad result", evidence.state["error"]
    assert_equal 4, evidence.verification.dig("result", "project_id")
  end

  test "mismatched linked work items cannot be reported as genuine" do
    evidence = NevaehIntelligences::TicketEvidence.new(ticket({"nevaeh" => {"intent_key" => "studio.project.create", "work_item_id" => 123, "correlation_id" => "right"}}))
    klass = DymondDispatch::WorkItem
    original = klass.method(:find_by)
    klass.define_singleton_method(:find_by) { |**_args| FakeItem.new(id: 123, kind: "studio.project.create", correlation_id: "wrong", status: "done") }
    assert_equal "unavailable / mismatch", evidence.work_item_status
  ensure
    klass.define_singleton_method(:find_by, original) if original
  end
end
