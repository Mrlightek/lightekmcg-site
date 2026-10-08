# frozen_string_literal: true

require "rails/generators"

module Studio
  module Generators
    class BlueprintGenerator < Rails::Generators::Base
      namespace "studio:blueprint"

      argument :blueprint_key,
        type: :string,
        required: true,
        banner: "BLUEPRINT_KEY"

      class_option :source,
        type: :string,
        default: nil,
        desc: "Canonical blueprint JSON path"

      class_option :force,
        type: :boolean,
        default: false,
        desc: "Overwrite generated artifacts"

      def generate_blueprint
        result = Studio::Blueprint::Generator.call(
          source: options[:source].presence || blueprint_key,
          force: options[:force]
        )

        result.fetch("artifacts").each do |artifact|
          say_status :create, artifact.fetch("path"), :green
        end

        say_status :blueprint, result.dig("blueprint", "key"), :green
        say_status :capabilities,
                   result.dig("blueprint", "actions").length.to_s,
                   :green
      rescue Studio::Blueprint::Compiler::InvalidBlueprint,
             Thor::Error => e
        raise Thor::Error, e.message
      end
    end
  end
end
