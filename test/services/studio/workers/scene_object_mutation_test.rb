# frozen_string_literal: true

require "test_helper"

module Studio
  module Workers
    class SceneObjectMutationTest < ActiveSupport::TestCase
      setup do
        @project =
          StudioProject.create!(
            name:
              "PWA SceneObject Test"
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
              "Scene 1"
          )
      end

      test "create transform duplicate and destroy SceneObjects" do
        created =
          SceneObjectMutation.perform(
            "create",
            {
              scene_id:
                @scene.id,

              name:
                "Cube 1",

              object_type:
                "cube",

              allow_overlap:
                false
            }
          )

        assert_equal(
          "created",
          created.fetch(
            "mutation"
          )
        )

        object =
          SceneObject.find(
            created.fetch(
              "object_id"
            )
          )

        assert_equal(
          "Cube 1",
          object.name
        )

        transformed =
          SceneObjectMutation.perform(
            "transform",
            {
              scene_id:
                @scene.id,

              object_id:
                object.id,

              attributes: {
                name:
                  "Hero Cube",

                allow_overlap:
                  true,

                location: [
                  1.0,
                  2.0,
                  3.0
                ],

                rotation: [
                  10.0,
                  20.0,
                  30.0
                ],

                scale: [
                  2.0,
                  2.5,
                  3.0
                ]
              }
            }
          )

        assert_equal(
          "transformed",
          transformed.fetch(
            "mutation"
          )
        )

        object.reload

        assert_equal(
          "Hero Cube",
          object.name
        )

        assert_equal(
          [
            1.0,
            2.0,
            3.0
          ],
          object.definition.fetch(
            "location"
          )
        )

        assert_equal(
          [
            10.0,
            20.0,
            30.0
          ],
          object.definition.fetch(
            "rotation"
          )
        )

        assert_equal(
          [
            2.0,
            2.5,
            3.0
          ],
          object.definition.fetch(
            "scale"
          )
        )

        duplicated =
          SceneObjectMutation.perform(
            "duplicate",
            {
              scene_id:
                @scene.id,

              object_id:
                object.id
            }
          )

        assert_equal(
          "duplicated",
          duplicated.fetch(
            "mutation"
          )
        )

        duplicate =
          SceneObject.find(
            duplicated.fetch(
              "object_id"
            )
          )

        assert_not_equal(
          object.id,
          duplicate.id
        )

        assert_equal(
          2,
          @scene.scene_objects.count
        )

        destroyed =
          SceneObjectMutation.perform(
            "destroy",
            {
              scene_id:
                @scene.id,

              object_id:
                duplicate.id
            }
          )

        assert_equal(
          "destroyed",
          destroyed.fetch(
            "mutation"
          )
        )

        assert_equal(
          true,
          destroyed.fetch(
            "object_absent"
          )
        )

        assert_not(
          SceneObject.exists?(
            duplicate.id
          )
        )
      end
    end
  end
end
