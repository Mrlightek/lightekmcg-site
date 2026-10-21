# frozen_string_literal: true
require "test_helper"
require "json"

class GithubDevelopmentPlanV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    assert item
    issue = {"number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"}
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 plan", category: "technical", priority: "high", status: "open", urgency: 5,
      extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
    assert_equal :attached, NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end

  def plan
    NevaehIntelligences::GithubDevelopmentPlanV7a.from_ticket(ticket: @ticket)
  end

  def test_generates_inert_plan_with_ticket_traceability
    p = plan
    assert_equal "planning_only", p.fetch("status")
    assert_equal @ticket.id, p.fetch("ticket_id")
    assert_equal "STUDIO-203", p.fetch("tracking_key")
    assert_equal "capability.build", p.fetch("required_capability")
    assert_equal false, p.fetch("execution_enabled")
    assert_equal false, p.dig("gatekeeper", "production_execution_allowed")
    assert_equal true, p.dig("gatekeeper", "authorization_required")
    assert_equal %w[inspect design implement verify register release], p.fetch("steps").map { |s| s.fetch("id") }
  end

  def test_deterministic_and_immutable
    a = plan
    assert_equal a, plan
    assert_match(/\A[0-9a-f]{64}\z/, a.fetch("fingerprint"))
    assert_raises(FrozenError) { a.fetch("dependencies") << "unsafe" }
    assert_raises(FrozenError) { a.fetch("steps").first["task"] = "unsafe" }
  end

  def test_does_not_change_ticket_or_create_extra_events
    before_fields = @ticket.reload.extra_fields.deep_dup
    before_events = @ticket.events.count
    plan
    assert_equal before_fields, @ticket.reload.extra_fields
    assert_equal before_events, @ticket.events.count
    assert_nil @ticket.extra_fields.dig("nevaeh", "work_item_id")
  end

  def test_rejects_tracking_identity_change
    @ticket.update!(extra_fields: @ticket.extra_fields.deep_merge("project_tracking" => {"key" => "STUDIO-204"}))
    assert_raises(NevaehIntelligences::GithubDevelopmentPlanV7a::Rejected) { plan }
  end

  def test_rejects_reserved_ticket
    @ticket.update!(extra_fields: @ticket.extra_fields.deep_merge("nevaeh" => {"execution_status" => "dispatch_reserved"}))
    assert_raises(NevaehIntelligences::GithubDevelopmentPlanV7a::Rejected) { plan }
  end

  def test_rejects_modified_execution_policy
    fields = @ticket.extra_fields.deep_dup
    fields.fetch("nevaeh_work_order").fetch("execution_policy")["production_allowed"] = true
    @ticket.update!(extra_fields: fields)
    assert_raises(StandardError) { plan }
  end
end
