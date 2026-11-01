# frozen_string_literal: true
module NevaehIntelligences
  module StructuredWorkers
    class CreateStudioProject
      def self.perform(inputs, actor:, ticket:)
        raise StructuredTicket::Invalid, "Studio project permission denied" unless Ability.new(actor).can?(:create, StudioProject)
        Studio::Workers::ProjectCreation.perform("create", inputs.merge("intent_key" => "production", "start_mode_key" => "blank")).deep_stringify_keys
      end

      def self.verify!(inputs, output, actor:)
        project = StudioProject.find(output.fetch("project_id"))
        production = Production.find_by!(id: output.fetch("production_id"), studio_project_id: project.id)
        StudioScene.find_by!(id: output.fetch("default_scene_id"), studio_project_id: project.id, production_id: production.id)
        raise StructuredTicket::Invalid, "Studio acceptance failed" unless project.name == inputs["name"]
        true
      end
    end
  end
end
