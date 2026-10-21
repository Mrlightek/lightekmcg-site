# frozen_string_literal: true
require "test_helper"

class GatekeeperExecutionBoundaryV2eTest < ActiveSupport::TestCase
  def ensure_capability_fixture!
    existing = NevaehCapability.find_by(gatekeeper_capability: "studio.project.create") || NevaehCapability.find_by(slug: "studio.project.create")
    return existing if existing

    NevaehCapability.create!(
      name: "Studio Project Create V2E Test",
      slug: "studio.project.create",
      domain: "studio",
      intent_name: "studio.project.create",
      subject_type: "Marlon::Ticket",
      handler: "Studio::Workers::ProjectCreate",
      queue: "default",
      priority: 2,
      gatekeeper_capability: "studio.project.create",
      enabled: true
    )
  end

  def admin
    User.create!(email_address: "v2e-boundary-#{SecureRandom.hex(8)}@example.test", first_name: "Gate", last_name: "Policy", role: "admin", password: "temporary-test-password")
  end

  def ticket
    t = Marlon::Ticket.create!(title: "Gatekeeper V2E", category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5, status: "open")
    order = NevaehIntelligences::WorkOrder.template.merge("objective" => "Create project", "inputs" => {"name" => "Authorized Proof"}, "acceptance_criteria" => ["Project persisted"], "execution_policy" => {"environment" => Rails.env, "approval" => "gatekeeper"})
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: order)
    t
  end

  test "Gatekeeper denies forged actor and revision context" do
    t = ticket
    record = ensure_capability_fixture!
    assert record, "Gatekeeper capability fixture must exist; do not skip authorization tests"
    assert record.enabled?, "Gatekeeper capability fixture must be enabled"
    digest = NevaehIntelligences::TicketApproval.fingerprint(t.extra_fields.fetch("nevaeh_work_order"))
    inputs_digest = NevaehIntelligences::TicketApproval.fingerprint({"name" => "Authorized Proof"})
    context = {"authorization_scope" => "nevaeh_ticket_dispatch_v2e", "actor_id" => -1, "ticket_id" => t.id, "environment" => Rails.env, "work_order_sha256" => digest, "inputs_sha256" => inputs_digest}
    assert_raises(Gatekeeper::AuthorizationDenied) { Gatekeeper.authorize_capability!(capability: "studio.project.create", subject: t, context: context) }
    context["actor_id"] = admin.id
    context["work_order_sha256"] = "f" * 64
    assert_raises(Gatekeeper::AuthorizationDenied) { Gatekeeper.authorize_capability!(capability: "studio.project.create", subject: t, context: context) }
  end

  test "denied Gatekeeper decision cannot reserve ticket or call queue" do
    t = ticket
    actor = admin
    calls = 0
    gate = Gatekeeper.method(:authorize_capability!)
    dispatch = NevaehIntelligences::Dispatch.method(:call)
    Gatekeeper.define_singleton_method(:authorize_capability!) { |**_kwargs| raise Gatekeeper::AuthorizationDenied.new(Gatekeeper::AuthorizationDecision.new(allowed: false, capability: "studio.project.create", reason: "policy denied")) }
    NevaehIntelligences::Dispatch.define_singleton_method(:call) { |**_kwargs| calls += 1; raise "queue called" }
    error = assert_raises(NevaehIntelligences::TicketExecution::InvalidTicket) do
      NevaehIntelligences::TicketExecution.dispatch!(ticket: t, actor: actor, payload: {name: "Authorized Proof"})
    end
    assert_match(/Gatekeeper denied/, error.message)
    assert_equal 0, calls
    assert_nil t.reload.extra_fields.to_h.dig("nevaeh", "execution_status")
  ensure
    Gatekeeper.define_singleton_method(:authorize_capability!, gate) if gate
    NevaehIntelligences::Dispatch.define_singleton_method(:call, dispatch) if dispatch
  end
end
