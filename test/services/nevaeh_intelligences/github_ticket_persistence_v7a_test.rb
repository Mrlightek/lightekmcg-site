# frozen_string_literal: true
require "test_helper"
require "json"

class GithubTicketPersistenceV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    issue = {"number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"}
    @proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 capability", category: "technical", priority: "high",
      status: "open", urgency: 5, extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
  end

  def test_attaches_one_inert_work_order_and_does_not_dispatch
    assert_equal :attached, persist
    @ticket.reload
    order = NevaehIntelligences::WorkOrder.read!(ticket: @ticket)
    assert_equal "build", order.fetch("work_type")
    assert_equal "test", order.dig("execution_policy", "environment")
    assert_equal false, order.dig("execution_policy", "execution_enabled")
    assert_equal "inert", @ticket.extra_fields.dig("nevaeh_github_import", "import_status")
    assert_nil @ticket.extra_fields.dig("nevaeh", "work_item_id")
  end

  def test_repeated_import_is_idempotent
    assert_equal :attached, persist
    assert_equal :unchanged, persist
    assert_equal 1, @ticket.events.where(action: "nevaeh_github_work_order_imported").count
  end

  def test_conflicting_ticket_identity_rejected
    @ticket.update!(extra_fields: {"project_tracking" => {"key" => "STUDIO-204"}})
    assert_raises(NevaehIntelligences::GithubTicketPersistenceV7a::Rejected) { persist }
  end

  def test_other_ticket_owns_tracking_key
    other = Marlon::Ticket.create!(title: "duplicate", category: "technical", priority: "high",
      status: "open", urgency: 5, extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
    assert other.persisted?
    assert_raises(NevaehIntelligences::GithubTicketPersistenceV7a::Rejected) { persist }
  end

  def test_tampered_proposal_rejected
    bad = Marshal.load(Marshal.dump(@proposal))
    bad["objective"] = "malicious edit"
    assert_raises(NevaehIntelligences::GithubTicketPersistenceV7a::Rejected) do
      NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: bad)
    end
  end

  def test_rejects_reserved_ticket
    @ticket.update!(extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}, "nevaeh" => {"execution_status" => "dispatch_reserved"}})
    assert_raises(NevaehIntelligences::GithubTicketPersistenceV7a::Rejected) { persist }
  end

  private
  def persist
    NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: @proposal)
  end
end
