# frozen_string_literal: true

module Studio
  module Workers
    class ProjectCreation
      ACTIONS = %w[create].freeze

      def self.perform(action, payload = {})
        new(action: action, payload: payload).perform
      end

      def initialize(action:, payload:)
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
      end

      def perform
        raise ArgumentError, "Unsupported Studio project operation" unless ACTIONS.include?(@action)

        name = @payload.fetch("name").to_s.strip
        description = @payload.fetch("description", "").to_s.strip
        raise ArgumentError, "Project name is required" if name.empty?

        # Creation is intent-driven: a creator receives a usable hierarchy,
        # never an unassigned scene that must be repaired later.
        intent_key = @payload.fetch("intent_key", "production").to_s.strip
        start_mode_key = @payload.fetch("start_mode_key", "blank").to_s.strip
        raise ArgumentError, "Creation intent is required" if intent_key.empty?
        raise ArgumentError, "Starting mode is required" if start_mode_key.empty?

        # Map supported creator intents to existing Production::KINDS.
        # Unknown intentions fail closed until a blueprint defines their shape.
        production_kind = {
          "production" => "general",
          "scene" => "general",
          "character" => "general",
          "environment" => "general",
          "prop" => "general",
          "vehicle" => "general",
          "architecture" => "general",
          "effect" => "general",
          "material" => "general",
          "template" => "general"
        }.fetch(intent_key) do
          raise ArgumentError, "Unsupported creation intent: #{intent_key}"
        end

        project = nil
        production = nil
        scene = nil
        StudioProject.transaction do
          project = StudioProject.create!(name: name, description: description)
          production = Production.create!(
            studio_project: project,
            name: name,
            kind: production_kind,
            status: "development",
            metadata: {
              "creation_intent" => intent_key,
              "start_mode" => start_mode_key
            }
          )
          # StudioProject's existing after_create callback makes Scene 1.
          # Attach it rather than manufacturing a duplicate scene.
          scene = project.studio_scenes.order(:id).first!
          scene.update!(production: production)
        end
        {
          "mutation" => "created",
          "project_id" => project.id,
          "production_id" => production.id,
          "default_scene_id" => scene.id,
          "project_persisted" => project.persisted?,
          "production_persisted" => production.persisted?,
          "scene_persisted" => scene.persisted?
        }
      end
    end
  end
end
