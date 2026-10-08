# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Studio
  module Blueprint
    class GeneratorTest < ActiveSupport::TestCase
      test "materializes Studio architecture with provenance" do
        Dir.mktmpdir("lightek-studio-blueprint") do |directory|
          result = Generator.call(source: source_definition, root: directory)
          artifacts = result.fetch("artifacts")

          assert_equal 9, artifacts.length

          artifacts.each do |artifact|
            path = File.join(directory, artifact.fetch("path"))
            assert File.file?(path), "Expected generated artifact #{path}"
          end

          ruby_artifacts =
            artifacts.select do |artifact|
              artifact.fetch("path").end_with?(".rb")
            end

          ruby_artifacts.each do |artifact|
            ruby_path =
              File.join(
                directory,
                artifact.fetch("path")
              )

            assert_nothing_raised do
              RubyVM::InstructionSequence.compile(
                File.read(ruby_path)
              )
            end
          end

          worker_path = File.join(
            directory,
            "app/services/studio/workers/generated/environment_contract.rb"
          )
          worker_source = File.read(worker_path)
          assert_includes worker_source, "Studio::Blueprint::Runtime.perform"

          pwa = JSON.parse(
            File.read(
              File.join(
                directory,
                "config/studio/generated/pwa/environment_contract.json"
              )
            )
          )

          assert_equal "studio_create_blueprint", pwa["contract_type"]
          assert_equal "Environment", pwa["label"]

          records = Marlon::GeneratedArtifact.where(
            blueprint_key: "studio:environment_contract"
          )

          assert_equal 9, records.count

          record = records.find_by!(artifact_type: "pwa_contract")
          assert_equal "environment_contract", record.metadata["studio_blueprint_key"]
          assert_match(
            /\A[0-9a-f]{64}\z/,
            record.metadata["studio_blueprint_source_sha256"]
          )
          assert_equal "Studio::Blueprint::Generator", record.metadata["generated_by"]
        end
      end

      private

      def source_definition
        {
          "schema_version" => 1,
          "key" => "environment_contract",
          "name" => "Environment",
          "description" => "Create an environment.",
          "actions" => [{"name" => "create"}],
          "runtime" => {"provider" => "blender", "enabled" => false},
          "pwa" => {
            "label" => "Environment",
            "start_modes" => [
              {"key" => "blank", "label" => "Start Blank"}
            ]
          },
          "inputs" => {
            "type" => "object",
            "properties" => {"name" => {"type" => "string"}},
            "required" => ["name"]
          },
          "template" => {"kind" => "environment", "defaults" => {}}
        }
      end
    end
  end
end
