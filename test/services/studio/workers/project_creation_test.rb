# frozen_string_literal: true

require "test_helper"

class StudioProjectCreationWorkerTest < ActiveSupport::TestCase
  test "creates a persisted project, default scene, and bootstrap-visible record" do
    result = Studio::Workers::ProjectCreation.perform("create", {
      name: "Creator Project", description: "A film concept",
      intent_key: "production", start_mode_key: "blank"
    })
    assert result.fetch("project_persisted")
    project = StudioProject.find(result.fetch("project_id"))
    assert_equal "Creator Project", project.name
    assert_equal "A film concept", project.description
    assert_equal 1, project.studio_scenes.count
    assert_equal 1, project.productions.count
    production = project.productions.first
    scene = project.studio_scenes.first
    assert_equal production.id, scene.production_id
    assert_equal result.fetch("production_id"), production.id
    assert_equal result.fetch("default_scene_id"), scene.id
    assert_equal "production", production.metadata.fetch("creation_intent")
    assert_equal "blank", production.metadata.fetch("start_mode")
    snapshot = Studio::Workers::Pwa.perform("bootstrap")
    row = snapshot.fetch("projects").find { |entry| entry.fetch("id") == project.id }
    assert row
    assert_empty row.fetch("unassigned_scenes")
    assert_equal scene.id, row.fetch("productions").first.fetch("scenes").first.fetch("id")
  ensure
    project&.destroy!
  end

  test "unsupported intent fails without leaving a project" do
    assert_no_difference "StudioProject.count" do
      assert_no_difference "Production.count" do
        assert_raises(ArgumentError) do
          Studio::Workers::ProjectCreation.perform("create", {
            name: "Unknown", intent_key: "undefined-kind", start_mode_key: "blank"
          })
        end
      end
    end
  end

  test "rejects blank project names" do
    assert_no_difference "StudioProject.count" do
      assert_raises(ArgumentError) { Studio::Workers::ProjectCreation.perform("create", {name: " "}) }
    end
  end
end
