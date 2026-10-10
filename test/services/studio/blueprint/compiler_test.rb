# frozen_string_literal: true

require "test_helper"

module Studio
  module Blueprint
    class CompilerTest < ActiveSupport::TestCase
      test "compiles intent-first Studio blueprint with safe defaults" do
        compiled = Compiler.call(source: source_definition)

        assert_equal 1, compiled["schema_version"]
        assert_equal "character_contract", compiled["key"]
        assert_equal(
          "Studio::Workers::Generated::CharacterContract",
          compiled.dig("runtime", "handler")
        )
        assert_equal false, compiled.dig("runtime", "enabled")
        assert_nil compiled.dig("runtime", "execution_handler")

        action = compiled.fetch("actions").first
        assert_equal "studio.character_contract.create", action["capability"]
        assert_equal "create_studio_character_contract", action["intent_name"]
        assert_equal(
          "studio.character_contract.create.requested",
          action["event_type"]
        )
        assert_equal "photo", compiled.dig("pwa", "start_modes", 0, "key")
        assert_match(/\A[0-9a-f]{64}\z/, compiled.dig("provenance", "source_sha256"))
      end

      test "digest preserves false values" do
        one = source_definition
        one["runtime"] = {"enabled" => false}

        two = source_definition
        two["runtime"] = {"enabled" => nil}

        first = Compiler.call(source: one).dig("provenance", "source_sha256")
        second = Compiler.call(source: two).dig("provenance", "source_sha256")

        refute_equal first, second
      end

      test "rejects duplicate capabilities" do
        definition = source_definition
        definition["actions"] = [
          {"name" => "create", "capability" => "studio.character_contract.execute"},
          {"name" => "update", "capability" => "studio.character_contract.execute"}
        ]

        error = assert_raises(Compiler::InvalidBlueprint) do
          Compiler.call(source: definition)
        end

        assert_match(/duplicate capabilities/, error.message)
      end

      test "preserves dynamic capability contracts and lifecycle" do
        definition = source_definition.merge(
          "version" => "2.1.0", "status" => "published",
          "intent" => {"examples" => ["Create a series"], "required_inputs" => ["creative_brief"]},
          "plan" => {"groups" => [
            {"key" => "development", "tasks" => ["outline"]},
            {"key" => "design", "depends_on" => ["development"], "tasks" => ["characters", "environments"]}
          ]},
          "execution" => {"mode" => "asynchronous", "authority" => "gatekeeper", "max_concurrency" => 3, "retries" => 2},
          "outputs" => {"editable_scripts" => true}, "review" => {"creative_approval" => true}
        )
        result = Compiler.call(source: definition)
        assert_equal "published", result.fetch("status")
        assert_equal "2.1.0", result.fetch("version")
        assert_equal 2, result.dig("plan", "groups").size
        assert_equal 3, result.dig("execution", "max_concurrency")
        assert_equal true, result.dig("outputs", "editable_scripts")
        assert_equal ["creative_brief"], result.dig("intent", "required_inputs")
      end

      test "rejects malformed execution authority and group dependencies" do
        definition = source_definition.merge("execution" => {"authority" => "unrestricted"})
        assert_raises(Compiler::InvalidBlueprint) { Compiler.call(source: definition) }
        definition = source_definition.merge("plan" => {"groups" => [{"key" => "design", "depends_on" => ["missing"], "tasks" => []}]})
        assert_raises(Compiler::InvalidBlueprint) { Compiler.call(source: definition) }
      end

      private

      def source_definition
        {
          "schema_version" => 1,
          "key" => "character_contract",
          "name" => "Character Contract",
          "description" => "Compile a character contract.",
          "actions" => [{"name" => "create"}],
          "runtime" => {"provider" => "blender"},
          "pwa" => {
            "start_modes" => [
              {"key" => "photo", "label" => "From Photo"}
            ]
          },
          "inputs" => {"type" => "object", "properties" => {}}
        }
      end
    end
  end
end
