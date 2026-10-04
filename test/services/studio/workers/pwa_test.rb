# frozen_string_literal: true

require "test_helper"

class StudioPwaWorkerTest < ActiveSupport::TestCase
  setup do
    @project =
      StudioProject.create!(
        name:
          "PWA Studio Project"
      )

    @production =
      Production.create!(
        studio_project:
          @project,

        name:
          "PWA Production",

        kind:
          "general",

        status:
          "development",

        metadata:
          {}
      )

    @scene =
      StudioScene.create!(
        studio_project:
          @project,

        production:
          @production,

        name:
          "PWA Scene"
      )

    @object =
      SceneObject.create!(
        studio_scene:
          @scene,

        name:
          "Hero Cube",

        object_type:
          "cube",

        position:
          0,

        definition: {
          "location" =>
            [1.0, 2.0, 3.0],

          "rotation" =>
            [0.0, 0.0, 0.0],

          "scale" =>
            [1.0, 1.0, 1.0]
        }
      )
  end

  teardown do
    @object&.destroy!
    @scene&.destroy!
    @production&.destroy!
    @project&.destroy!
  end

  test "bootstrap returns real project production scene and object hierarchy" do
    result =
      Studio::Workers::Pwa.perform(
        "bootstrap"
      )

    project =
      result
        .fetch(
          "projects"
        )
        .find do |record|
          record.fetch(
            "id"
          ) == @project.id
        end

    assert_not_nil project

    production =
      project
        .fetch(
          "productions"
        )
        .find do |record|
          record.fetch(
            "id"
          ) == @production.id
        end

    assert_not_nil production

    scene =
      production
        .fetch(
          "scenes"
        )
        .find do |record|
          record.fetch(
            "id"
          ) == @scene.id
        end

    assert_not_nil scene

    assert_equal(
      1,
      scene.fetch(
        "object_count"
      )
    )

    object =
      scene
        .fetch(
          "objects"
        )
        .first

    assert_equal(
      @object.id,
      object.fetch(
        "id"
      )
    )

    assert_equal(
      "cube",
      object.fetch(
        "object_type"
      )
    )

    assert_equal(
      [1.0, 2.0, 3.0],
      object
        .fetch(
          "definition"
        )
        .fetch(
          "location"
        )
    )

    assert_includes(
      result.fetch(
        "object_types"
      ),
      "camera"
    )
  end

  test "unsupported actions fail closed" do
    assert_raises(
      ArgumentError
    ) do
      Studio::Workers::Pwa.perform(
        "unknown"
      )
    end
  end
end
