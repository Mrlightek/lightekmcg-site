# frozen_string_literal: true
require "test_helper"

class StudioProductionBlueprintTaskGroupsTest < ActiveSupport::TestCase
  Registry = Studio::ProductionBlueprints::Registry
  Groups = Studio::ProductionBlueprints::TaskGroups

  def film_plan
    Registry.plan!(intent_key: "production", production_type: "film", start_mode_key: "blank", name: "Example Film")
  end

  test "sibling tasks sharing prerequisite group fire together after trigger" do
    flow = Groups.new(film_plan)
    root = flow.ready_groups(completed_tasks: [])
    assert_equal [["intent_review"]], root.map { |g| g.fetch("tasks") }
    ready = flow.ready_groups(completed_tasks: ["intent_review"], claimed_groups: root.map { |g| g.fetch("key") })
    assert_equal 1, ready.length
    assert_equal %w[asset_inventory creative_brief].sort, ready.first.fetch("tasks").sort
    assert_equal "parallel_eligible", ready.first.fetch("dispatch_mode")
  end

  test "multi-prerequisite group stays blocked until all completion receipts exist" do
    flow = Groups.new(film_plan)
    partially_done = flow.ready_groups(completed_tasks: %w[intent_review creative_brief creative_outline])
    refute partially_done.any? { |g| g.fetch("tasks").include?("character_plan") }
    ready = flow.ready_groups(completed_tasks: %w[intent_review asset_inventory creative_brief creative_outline])
    siblings = ready.find { |g| g.fetch("tasks").include?("character_plan") }
    assert_equal %w[character_plan environment_plan].sort, siblings.fetch("tasks").sort
  end

  test "claimed group cannot be dispatched a second time" do
    flow = Groups.new(film_plan)
    root = flow.ready_groups(completed_tasks: []).first
    assert_empty flow.ready_groups(completed_tasks: [], claimed_groups: [root.fetch("key")])
  end

  test "invalid DAG and orphan dependencies fail closed" do
    assert_raises(Groups::InvalidPlan) { Groups.new({"tasks" => [{"key" => "a", "depends_on" => ["missing"]}]}) }
    assert_raises(Groups::InvalidPlan) { Groups.new({"tasks" => [{"key" => "a", "depends_on" => ["b"]}, {"key" => "b", "depends_on" => ["a"]}]}) }
  end

  test "standalone asset has its own group plan" do
    plan = Registry.plan!(intent_key: "character", start_mode_key: "generate", name: "Iris")
    group = Groups.new(plan).groups
    assert group.any? { |row| row.fetch("tasks") == ["asset_design"] }
    refute group.any? { |row| row.fetch("tasks").include?("script_draft") }
  end
end
