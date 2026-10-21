# frozen_string_literal: true
require "test_helper"

class NevaehWorkOrderExecutionGuardTest < ActiveSupport::TestCase
  def execution_actor
    User.create!(email_address: "nevaeh-test-#{SecureRandom.hex(8)}@example.test",
      first_name: "Nevaeh", last_name: "Test", role: "admin", password: "temporary-test-password")
  end

  def order
    capability = NevaehCapability.find_by(gatekeeper_capability: "studio.project.create") || NevaehCapability.find_by(slug: "studio.project.create")
    if capability
      raise "STOP: existing Gatekeeper fixture is disabled or incompatible" unless capability.enabled? && capability.subject_type == "Marlon::Ticket"
    else
      NevaehCapability.create!(
        name: "Studio Project Create V2E Test", slug: "studio.project.create",
        domain: "studio", intent_name: "studio.project.create",
        subject_type: "Marlon::Ticket", handler: "Studio::Workers::ProjectCreate",
        queue: "default", priority: 2,
        gatekeeper_capability: "studio.project.create", enabled: true
      )
    end
    NevaehIntelligences::WorkOrder.template.merge(
      "execution_policy" => NevaehIntelligences::WorkOrder.template.fetch("execution_policy").merge("environment" => Rails.env),
      "objective" => "Create Studio project",
      "inputs" => {"name" => "Guard Proof"},
      "acceptance_criteria" => ["Persist project, production, scene"]
    )
  end

  def ticket
    Marlon::Ticket.create!(title: "Nevaeh guard", category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open")
  end

  test "dispatch blocks missing actor before calling dispatcher" do
    t = ticket
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: order)
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) do
      NevaehIntelligences::WorkOrder.dispatch!(ticket: t, actor: nil)
    end
    assert_nil t.reload.extra_fields.to_h.dig("nevaeh", "work_item_id")
  end

  test "dispatch blocks mismatched environment" do
    t = ticket
    values = order
    values["execution_policy"] = {"environment" => Rails.env.test? ? "development" : "test", "approval" => "approved"}
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: values)
    actor = execution_actor
    assert_raises(NevaehIntelligences::WorkOrder::Invalid) do
      NevaehIntelligences::WorkOrder.dispatch!(ticket: t, actor: actor)
    end
  end

  test "ticket executor derives intent from persisted work order" do
    t = ticket
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: order)
    assert_equal "studio.project.create", t.reload.extra_fields.dig("nevaeh_work_order", "intent_key")
    actor = execution_actor
    dispatch = NevaehIntelligences::Dispatch
    original = dispatch.method(:call)
    dispatch.define_singleton_method(:call) { |**_args| {"work_item_id" => 928137, "correlation_id" => "guard-proof"} }
    NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: actor, payload: {name: "Guard Proof"})
    assert_equal 928137, t.reload.extra_fields.dig("nevaeh", "work_item_id")
    assert_equal "in_progress", t.status
    assert_equal "nevaeh_dispatched", t.events.order(:id).last.action
  ensure
    dispatch.define_singleton_method(:call, original) if original
  end
end
