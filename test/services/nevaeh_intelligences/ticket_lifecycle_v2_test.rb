# frozen_string_literal: true
require "test_helper"
require "json"

class NevaehTicketLifecycleV2Test < ActiveSupport::TestCase
  CAPABILITY = "studio.project.create"
  FakeItem = Struct.new(:id, :kind, :status, :correlation_id, :result, :error, keyword_init: true)

  def ticket_for(item, project_name:)
    Marlon::Ticket.create!(
      title: "[NEVAEH LIFECYCLE V2] #{SecureRandom.hex(4)}",
      category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "in_progress",
      extra_fields: {
        "unrelated" => "preserve",
        "nevaeh" => {
          "intent_key" => CAPABILITY,
          "work_item_id" => item.id,
          "correlation_id" => item.correlation_id,
          "expected_project_name" => project_name,
          "execution_status" => "dispatched"
        }
      }
    )
  end

  def fake_item(status:, result: {}, id: 990001, correlation_id: SecureRandom.uuid, kind: CAPABILITY, error: nil)
    FakeItem.new(id: id, kind: kind, status: status, result: result, correlation_id: correlation_id, error: error)
  end

  # Minitest mock is not installed in this project: use a Ruby-native temporary
  # override and restore the original method even when the assertion fails.
  def with_work_item(item)
    klass = DymondDispatch::WorkItem
    original = klass.method(:find)
    klass.define_singleton_method(:find) do |id|
      raise ActiveRecord::RecordNotFound, "unknown work item" unless id.to_s == item.id.to_s
      item
    end
    yield
  ensure
    klass.define_singleton_method(:find, original) if original
  end

  test "pending work stays open and does not claim success" do
    item = fake_item(status: "running")
    ticket = ticket_for(item, project_name: "Pending proof")
    with_work_item(item) do
      assert_equal "pending", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket)
    end
    assert_equal "in_progress", ticket.reload.status
    assert_nil ticket.resolved_at
    assert_equal "dispatched", ticket.extra_fields.dig("nevaeh", "execution_status")
    assert_equal 0, ticket.events.count
  end

  test "real created hierarchy verifies and resolves once" do
    name = "Lifecycle Proof #{SecureRandom.hex(5)}"
    result = Studio::Workers::ProjectCreation.perform("create", {"name" => name, "intent_key" => "production", "start_mode_key" => "blank"})
    item = fake_item(status: "done", result: result)
    ticket = ticket_for(item, project_name: name)
    with_work_item(item) do
      assert_equal "resolved", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket)
      assert_equal "resolved", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket.reload)
    end
    ticket.reload
    assert_equal "resolved", ticket.status
    assert ticket.resolved_at.present?
    assert_equal "verified", ticket.extra_fields.dig("nevaeh", "execution_status")
    assert_equal result.fetch("project_id"), ticket.extra_fields.dig("nevaeh", "verification", "project_id")
    assert_equal item.correlation_id, ticket.extra_fields.dig("nevaeh", "verification", "correlation_id")
    assert_equal "preserve", ticket.extra_fields.fetch("unrelated")
    assert_equal 1, ticket.events.where(action: "nevaeh_verified_and_resolved").count
  end

  test "a done work item cannot close ticket without a matching output" do
    name = "Expected project #{SecureRandom.hex(5)}"
    result = Studio::Workers::ProjectCreation.perform("create", {"name" => "Different project", "intent_key" => "production"})
    item = fake_item(status: "done", result: result)
    ticket = ticket_for(item, project_name: name)
    with_work_item(item) do
      assert_equal "verification_failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket)
      assert_equal "verification_failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket.reload)
    end
    assert_equal "in_progress", ticket.reload.status
    assert_nil ticket.resolved_at
    assert_equal 1, ticket.events.where(action: "nevaeh_verification_failed").count
    assert_equal "verification_failed", ticket.extra_fields.dig("nevaeh", "execution_status")
  end

  test "failed work preserves error and does not produce duplicate events" do
    item = fake_item(status: "failed", error: "Worker failed to generate requested asset")
    ticket = ticket_for(item, project_name: "Error proof")
    with_work_item(item) do
      assert_equal "failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket)
      assert_equal "failed", NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket.reload)
    end
    assert_equal "in_progress", ticket.reload.status
    assert_includes ticket.extra_fields.dig("nevaeh", "error"), "Worker failed"
    assert_equal 1, ticket.events.where(action: "nevaeh_execution_failed").count
  end

  test "cannot claim another ticket work item or correlation" do
    item = fake_item(status: "done", result: {"mutation" => "created"})
    other = fake_item(status: "done", id: item.id + 1, correlation_id: item.correlation_id)
    ticket = ticket_for(item, project_name: "Wrong item")
    with_work_item(other) do
      assert_raises(ActiveRecord::RecordNotFound) { NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket) }
    end
    mismatch = fake_item(status: "done", id: item.id, correlation_id: SecureRandom.uuid)
    with_work_item(mismatch) do
      assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) { NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket) }
    end
    wrong_kind = fake_item(status: "done", id: item.id, correlation_id: item.correlation_id, kind: "studio.other.create")
    with_work_item(wrong_kind) do
      assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) { NevaehIntelligences::TicketExecution.reconcile!(ticket: ticket) }
    end
    assert_equal "in_progress", ticket.reload.status
    assert_equal 0, ticket.events.count
  end
end
