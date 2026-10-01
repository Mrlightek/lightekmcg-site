# frozen_string_literal: true

module Studio
  module Workers
    class SceneObjectMutation
      ACTIONS = %w[
        create
        transform
        duplicate
        destroy
      ].freeze

      def self.perform(action, payload = {})
        new(
          action: action,
          payload: payload
        ).perform
      end

      def initialize(action:, payload:)
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
      end

      def perform
        unless ACTIONS.include?(action)
          raise ArgumentError,
                "Unsupported SceneObject mutation #{action.inspect}"
        end

        case action
        when "create"
          create_object
        when "transform"
          transform_object
        when "duplicate"
          duplicate_object
        when "destroy"
          destroy_object
        end
      end

      private

      attr_reader :action, :payload

      def domain
        @domain ||= DymondStudio::StudioV2Domain.new
      end

      def scene
        @scene ||= StudioScene.find(
          payload.fetch("scene_id")
        )
      end

      def scene_object
        @scene_object ||=
          scene.scene_objects.find(
            payload.fetch("object_id")
          )
      end

      def create_object
        object =
          domain.create_scene_object(
            scene: scene,
            name: payload.fetch("name"),
            object_type:
              payload.fetch("object_type"),
            definition:
              payload.fetch("definition", {}),
            allow_overlap:
              payload.fetch(
                "allow_overlap",
                false
              )
          )

        result_for(
          object,
          mutation: "created"
        )
      end

      def transform_object
        object =
          domain.update_scene_object(
            scene_object: scene_object,
            attributes:
              payload.fetch(
                "attributes",
                {}
              )
          )

        result_for(
          object,
          mutation: "transformed"
        )
      end

      def duplicate_object
        object =
          domain.duplicate_scene_object(
            scene_object: scene_object
          )

        result_for(
          object,
          mutation: "duplicated"
        )
      end

      def destroy_object
        object_id = scene_object.id
        scene_id = scene.id

        domain.destroy_scene_object(
          scene_object: scene_object
        )

        {
          "mutation" => "destroyed",
          "scene_id" => scene_id,
          "object_id" => object_id,
          "object_absent" =>
            !SceneObject.exists?(object_id)
        }
      end

      def result_for(object, mutation:)
        {
          "mutation" => mutation,
          "scene_id" =>
            object.studio_scene_id,
          "object_id" => object.id,
          "object_persisted" =>
            object.persisted?,
          "object" => {
            "id" => object.id,
            "name" => object.name,
            "type" => object.object_type,
            "definition" =>
              object.definition.to_h
          }
        }
      end
    end
  end
end
