# frozen_string_literal: true
require "test_helper"
require "json"

class NevaehWorkOrderTest < ActiveSupport::TestCase
  def execution_actor
    User.create!(email_address: "nevaeh-test-#{SecureRandom.hex(8)}@example.test",
      first_name: "Nevaeh", last_name: "Test", role: "admin", password: "temporary-test-password")
  end

  def valid_order
    NevaehIntelligences::WorkOrder.template.merge(
      "objective" => "Create a usable Studio project",
      "inputs" => { "name" => "Work Order Proof", "intent_key" => "production", "start_mode_key" => "blank" },
      "acceptance_criteria" => ["Project, production and scene exist"]
    )
  end

  def new_ticket
    Marlon::Ticket.create!(title: "Nevaeh Work Order Proof", category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open", extra_fields: { "unrelated" => "keep" })
  end

  test "template is structured and versioned" do
    assert_equal 1, NevaehIntelligences::WorkOrder.template.fetch("version")
    assert_equal "studio.project.create", NevaehIntelligences::WorkOrder.template.fetch("intent_key")
  end

  test "attaches a validated order to the existing ticket and records evidence" do
    ticket = new_ticket
    order = NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: valid_order)
    assert_equal order, NevaehIntelligences::WorkOrder.read!(ticket: ticket.reload)
    assert_equal "keep", ticket.extra_fields.fetch("unrelated")
    assert_equal "nevaeh_work_order_registered", ticket.events.order(:id).last.action
  end

  test "cannot register an incomplete work order" do
    order = valid_order.merge("acceptance_criteria" => [])
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkOrder.attach!(ticket: new_ticket, attributes: order) }
  end

  test "does not replace an in-progress execution" do
    ticket = new_ticket
    ticket.update!(extra_fields: { "nevaeh" => { "work_item_id" => 59 } })
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: valid_order) }
  end

  test "production requires an explicit approval before dispatch" do
    ticket = new_ticket
    order = valid_order
    order["execution_policy"] = { "environment" => "production", "approval" => "gatekeeper" }
    NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: order)
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkOrder.dispatch!(ticket: ticket, actor: execution_actor) }
  end

  test "build commands can be stored but cannot execute until an executor is verified" do
    ticket = new_ticket
    order = valid_order.merge("work_type" => "build", "intent_key" => "studio.capability.build")
    NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: order)
    assert_equal "build", NevaehIntelligences::WorkOrder.read!(ticket: ticket).fetch("work_type")
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkOrder.dispatch!(ticket: ticket, actor: execution_actor) }
  end

  test "missing work order cannot dispatch" do
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) { NevaehIntelligences::WorkOrder.dispatch!(ticket: new_ticket, actor: Object.new) }
  end
end
