# frozen_string_literal: true

require "test_helper"

class StudioProductionBlueprintRegistryTest < ActiveSupport::TestCase
  Registry = Studio::ProductionBlueprints::Registry

  test "an explicit film production gets a non-generic blueprint and dependency plan" do
    plan = Registry.plan!(intent_key: "production", production_type: "film", start_mode_key: "blank", name: "First Feature")
    assert_equal "film", plan.fetch("blueprint_key")
    assert_equal "film", plan.fetch("production_kind")
    assert_includes plan.fetch("departments"), "cinematography"
    assert_equal "not_dispatched", plan.fetch("execution")
    task_names = plan.fetch("tasks").map { |task| task.fetch("key") }
    plan.fetch("tasks").each do |task|
      task.fetch("depends_on").each { |dependency| assert_includes task_names, dependency }
    end
  end

  test "documentary is distinct from film even when model kind overlaps" do
    plan = Registry.plan!(intent_key: "production", production_type: "documentary", start_mode_key: "blank", name: "Field Notes")
    assert_equal "documentary", plan.fetch("blueprint_key")
    assert_includes plan.fetch("departments"), "research"
    assert_includes plan.fetch("departments"), "rights"
  end

  test "asset intent is not forced into a production" do
    plan = Registry.plan!(intent_key: "character", start_mode_key: "generate", name: "Iris")
    assert_equal "standalone_asset", plan.fetch("blueprint_key")
    assert_nil plan.fetch("production_kind")
    assert_includes plan.fetch("tasks").map { |row| row.fetch("key") }, "asset_design"
  end

  test "ambiguous and unsupported intents fail closed" do
    assert_raises(Registry::ClarificationRequired) { Registry.plan!(intent_key: "production", start_mode_key: "blank", name: "Unknown") }
    assert_raises(Registry::UnsupportedIntent) { Registry.plan!(intent_key: "production", production_type: "space_opera", start_mode_key: "blank", name: "Unknown") }
    assert_raises(Registry::ClarificationRequired) { Registry.plan!(intent_key: "scene", start_mode_key: "blank", name: "A scene") }
  end

  test "plans are deterministic and independent" do
    first = Registry.plan!(intent_key: "production", production_type: "scripted_series", start_mode_key: "blank", name: "Echo")
    second = Registry.plan!(intent_key: "production", production_type: "scripted_series", start_mode_key: "blank", name: "Echo")
    assert_equal first, second
    first.fetch("departments") << "unexpected"
    refute_includes second.fetch("departments"), "unexpected"
  end
end
