# frozen_string_literal: true

module Studio
  module Workers
    class Pwa
      ACTIONS = %w[
        bootstrap
      ].freeze

      def self.perform(action, payload = {})
        new(
          action: action,
          payload: payload
        ).perform
      end

      def initialize(action:, payload:)
        @action =
          action.to_s

        @payload =
          payload
            .to_h
            .deep_stringify_keys
      end

      def perform
        unless ACTIONS.include?(action)
          raise ArgumentError,
                "Unsupported Studio PWA action: #{action}"
        end

        case action
        when "bootstrap"
          bootstrap
        end
      end

      private

      attr_reader :action,
                  :payload

      def studio
        @studio ||=
          DymondStudio::StudioV2Domain.new
      end

      def bootstrap
        projects =
          Array(
            studio.projects
          )

        project_payloads =
          projects.map do |project|
            project_payload(
              project
            )
          end

        {
          "surface" =>
            "studio",

          "projects" =>
            project_payloads,

          "project_count" =>
            project_payloads.length,

          "production_count" =>
            project_payloads.sum do |project|
              Array(
                project["productions"]
              ).length
            end,

          "scene_count" =>
            project_payloads.sum do |project|
              Array(
                project["scenes"]
              ).length
            end,

          "object_types" =>
            SceneObject::TYPES
        }
      end

      def project_payload(project)
        productions =
          Array(
            studio.productions(
              project:
                project
            )
          )

        scenes =
          Array(
            studio.scenes(
              project:
                project
            )
          )

        {
          "id" =>
            project.id,

          "name" =>
            project.name,

          "description" =>
            project.respond_to?(:description) ?
              project.description :
              nil,

          "created_at" =>
            iso8601(
              project.created_at
            ),

          "updated_at" =>
            iso8601(
              project.updated_at
            ),

          "productions" =>
            productions.map do |production|
              production_payload(
                production,
                scenes:
                  scenes.select do |scene|
                    scene.production_id ==
                      production.id
                  end
              )
            end,

          "scenes" =>
            scenes.map do |scene|
              scene_payload(
                scene
              )
            end,

          "unassigned_scenes" =>
            scenes
              .select do |scene|
                scene.production_id.nil?
              end
              .map do |scene|
                scene_payload(
                  scene
                )
              end
        }
      end

      def production_payload(
        production,
        scenes:
      )
        {
          "id" =>
            production.id,

          "studio_project_id" =>
            production.studio_project_id,

          "name" =>
            production.name,

          "kind" =>
            production.kind,

          "status" =>
            production.status,

          "metadata" =>
            production.metadata.to_h,

          "created_at" =>
            iso8601(
              production.created_at
            ),

          "updated_at" =>
            iso8601(
              production.updated_at
            ),

          "scenes" =>
            scenes.map do |scene|
              scene_payload(
                scene
              )
            end
        }
      end

      def scene_payload(scene)
        objects =
          scene
            .scene_objects
            .to_a

        {
          "id" =>
            scene.id,

          "studio_project_id" =>
            scene.studio_project_id,

          "production_id" =>
            scene.production_id,

          "name" =>
            scene.name,

          "settings" =>
            scene.settings.to_h,

          "object_count" =>
            objects.length,

          "objects" =>
            objects.map do |object|
              object_payload(
                object
              )
            end,

          "created_at" =>
            iso8601(
              scene.created_at
            ),

          "updated_at" =>
            iso8601(
              scene.updated_at
            ),

          "rails_fallback_path" =>
            rails_fallback_path(
              scene
            )
        }
      end

      def object_payload(object)
        {
          "id" =>
            object.id,

          "name" =>
            object.name,

          "object_type" =>
            object.object_type,

          "position" =>
            object.position,

          "definition" =>
            object.definition.to_h
        }
      end

      def rails_fallback_path(scene)
        return nil unless scene.production_id

        "/studio/productions/" \
          "#{scene.production_id}/scenes/" \
          "#{scene.id}"
      end

      def iso8601(value)
        value&.iso8601
      end
    end
  end
end
