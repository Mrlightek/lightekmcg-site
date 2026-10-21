# frozen_string_literal: true
require "test_helper"

class NevaehV2fIntegrityAuditTest < ActiveSupport::TestCase
  CAPABILITY = "studio.project.create"

  def actor
    User.create!(email_address: "v2f-#{SecureRandom.hex(9)}@example.test", first_name: "Security", last_name: "Proof", role: "admin", password: "temporary-test-password")
  end

  def capability!
    NevaehCapability.find_by(gatekeeper_capability: CAPABILITY) ||
      NevaehCapability.find_by(slug: CAPABILITY) ||
      NevaehCapability.create!(name: "Studio V2F Test", slug: CAPABILITY, domain: "studio", intent_name: CAPABILITY,
        subject_type: "Marlon::Ticket", handler: "Studio::Workers::ProjectCreate", queue: "default", priority: 2,
        gatekeeper_capability: CAPABILITY, enabled: true)
  end

  def ticket!
    t = Marlon::Ticket.create!(title: "V2F security", category: Marlon::TicketCategories.ids.first,
      priority: "medium", urgency: 5, status: "open")
    order = NevaehIntelligences::WorkOrder.template.merge("objective" => "Verify security",
      "inputs" => {"name" => "V2F Proof"}, "acceptance_criteria" => ["Creation verified"],
      "execution_policy" => {"environment" => Rails.env, "approval" => "gatekeeper"})
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: order)
    t
  end

  def with_dispatch_stub(&implementation)
    klass = NevaehIntelligences::Dispatch
    original = klass.method(:call)
    klass.define_singleton_method(:call, &implementation)
    yield if false
  ensure
    klass.define_singleton_method(:call, original) if original
  end

  test "disabled Nevaeh capability fails closed before reservation" do
    c = capability!
    original_enabled = c.enabled?
    c.update!(enabled: false)
    t = ticket!
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: actor, payload: {name: "V2F Proof"})
    end
    assert_match(/Gatekeeper denied/, error.message)
    assert_nil t.reload.extra_fields.to_h.dig("nevaeh", "execution_status")
  ensure
    c.update!(enabled: original_enabled) if c && !original_enabled.nil? && c.persisted?
  end

  test "modified inputs fail closed before reservation" do
    capability!
    t = ticket!
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: actor, payload: {name: "Forged"})
    end
    assert_match(/payload differs/i, error.message)
    assert_nil t.reload.extra_fields.to_h.dig("nevaeh", "execution_status")
  end

  test "existing reservation prevents replay before queue" do
    capability!
    t = ticket!
    fields = t.extra_fields.to_h.deep_stringify_keys
    fields["nevaeh"] = {"execution_status" => "dispatch_reserved", "reservation_id" => SecureRandom.uuid}
    t.update!(extra_fields: fields)
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: actor, payload: {name: "V2F Proof"})
    end
    assert_match(/already reserved/, error.message)
  end

  test "queue uncertainty records nonretryable state" do
    capability!
    t = ticket!
    user = actor
    dispatch = NevaehIntelligences::Dispatch
    original = dispatch.method(:call)
    count = 0
    dispatch.define_singleton_method(:call) { |**_args| count += 1; raise IOError, "transport ambiguous" }
    assert_raises(IOError) { NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: user, payload: {name: "V2F Proof"}) }
    assert_equal 1, count
    assert_equal "dispatch_uncertain", t.reload.extra_fields.to_h.dig("nevaeh", "execution_status")
    assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: user, payload: {name: "V2F Proof"})
    end
    assert_equal 1, count
  ensure
    dispatch.define_singleton_method(:call, original) if original
  end
end
