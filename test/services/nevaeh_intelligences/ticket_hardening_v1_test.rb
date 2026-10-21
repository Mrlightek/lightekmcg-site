# frozen_string_literal: true
require "test_helper"

class NevaehTicketHardeningV1Test < ActiveSupport::TestCase
  def actor
    User.create!(email_address: "hardening-#{SecureRandom.hex(8)}@example.test",
      first_name: "Nevaeh", last_name: "Operator", role: "admin", password: "temporary-test-password")
  end

  def prepared_ticket
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
    ticket = Marlon::Ticket.create!(title: "Dispatch hardening", category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open")
    order = NevaehIntelligences::WorkOrder.template.merge(
      "execution_policy" => NevaehIntelligences::WorkOrder.template.fetch("execution_policy").merge("environment" => Rails.env),
      "objective" => "Make a Studio project", "inputs" => {"name" => "Hardening Proof"},
      "acceptance_criteria" => ["Project and production persisted"])
    NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: order)
    ticket
  end

  def stub_dispatch(implementation)
    klass = NevaehIntelligences::Dispatch
    original = klass.method(:call)
    klass.define_singleton_method(:call, &implementation)
    yield
  ensure
    klass.define_singleton_method(:call, original) if original
  end

  test "reservation rejects a second dispatch before enqueue" do
    ticket = prepared_ticket
    worker = actor
    calls = 0
    test_context = self
    implementation = lambda do |**args|
      calls += 1
      test_context.assert_equal "dispatch_reserved", ticket.reload.extra_fields.dig("nevaeh", "execution_status")
      test_context.assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
        NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: worker, payload: {name: "Hardening Proof"})
      end
      {"work_item_id" => 813102, "correlation_id" => args.fetch(:correlation_id)}
    end
    receipt = nil
    stub_dispatch(implementation) do
      receipt = NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: worker, payload: {name: "Hardening Proof"})
    end
    assert_equal 1, calls
    assert_equal 813102, receipt.fetch("work_item_id")
    assert_equal "dispatched", ticket.reload.extra_fields.dig("nevaeh", "execution_status")
    assert_equal 1, ticket.events.where(action: "nevaeh_dispatched").count
  end

  test "dispatch exception is recorded without automatic retry" do
    ticket = prepared_ticket
    worker = actor
    calls = 0
    stub_dispatch(lambda { |**_args| calls += 1; raise RuntimeError, "transport lost" }) do
      assert_raises(RuntimeError) { NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: worker, payload: {name: "Hardening Proof"}) }
    end
    ticket.reload
    assert_equal 1, calls
    assert_equal "dispatch_uncertain", ticket.extra_fields.dig("nevaeh", "execution_status")
    assert_equal 1, ticket.events.where(action: "nevaeh_dispatch_uncertain").count
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: worker, payload: {name: "Hardening Proof"})
    end
  end

  test "non-employee and absent actors cannot dispatch" do
    ticket = prepared_ticket
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: nil, payload: {name: "Hardening Proof"})
    end
    outsider = User.create!(email_address: "client-#{SecureRandom.hex(8)}@example.test",
      first_name: "Test", last_name: "Client", role: "client", password: "temporary-test-password")
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: ticket, actor: outsider, payload: {name: "Hardening Proof"})
    end
    assert_equal "open", ticket.reload.status
  end
end
