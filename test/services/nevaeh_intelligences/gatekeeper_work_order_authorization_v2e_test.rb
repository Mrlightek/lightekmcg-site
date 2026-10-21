# frozen_string_literal: true
require "test_helper"

class GatekeeperWorkOrderAuthorizationV2eTest < ActiveSupport::TestCase
  def actor
    User.create!(email_address: "v2e-#{SecureRandom.hex(8)}@example.test", first_name: "Policy", last_name: "Test", role: "admin", password: "temporary-test-password")
  end

  def ticket_with_order
    t = Marlon::Ticket.create!(title: "V2E authority", category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5, status: "open")
    o = NevaehIntelligences::WorkOrder.template.merge("objective" => "Create a verified project", "inputs" => {"name" => "V2E"}, "acceptance_criteria" => ["Project persisted"], "execution_policy" => {"environment" => Rails.env, "approval" => "gatekeeper"})
    NevaehIntelligences::WorkOrder.attach!(ticket: t, attributes: o)
    [t, o]
  end

  test "tampered payload is denied before consulting Gatekeeper" do
    t, o = ticket_with_order
    assert_raises(NevaehIntelligences::GatekeeperWorkOrderAuthorization::Denied) do
      NevaehIntelligences::GatekeeperWorkOrderAuthorization.require_allowed!(ticket: t, actor: actor, order: o, payload: {name: "wrong"})
    end
  end

  test "unregistered capability fails closed through the real Gatekeeper" do
    t, o = ticket_with_order
    # No test fixture can confer authorization merely by claiming approval.
    # If a capability record exists in this database, disable only inside the transaction.
    NevaehCapability.transaction(requires_new: true) do
      records = NevaehCapability.where(slug: "studio.project.create").or(NevaehCapability.where(gatekeeper_capability: "studio.project.create"))
      records.update_all(enabled: false)
      assert_raises(NevaehIntelligences::GatekeeperWorkOrderAuthorization::Denied) do
        NevaehIntelligences::GatekeeperWorkOrderAuthorization.require_allowed!(ticket: t, actor: actor, order: o, payload: {name: "V2E"})
      end
      raise ActiveRecord::Rollback
    end
  end
end
