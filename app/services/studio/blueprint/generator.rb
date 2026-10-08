# frozen_string_literal: true

require "json"
require "pathname"

module Studio
  module Blueprint
    class Generator
      def self.call(source:, root: Rails.root, force: false)
        new(source: source, root: root, force: force).call
      end

      def initialize(source:, root: Rails.root, force: false)
        @source = source
        @root = Pathname(root)
        @force = force
      end

      def call
        artifacts = planned_artifacts
        artifacts.each do |artifact|
          write_artifact(
            artifact.fetch("path"),
            content_for(artifact.fetch("artifact_type"), artifacts),
            artifact.fetch("artifact_type")
          )
        end

        {"blueprint" => blueprint, "artifacts" => artifacts}
      end

      private

      attr_reader :source, :root, :force

      def blueprint
        @blueprint ||= Studio::Blueprint::Compiler.call(source: source, root: root)
      end

      def key
        blueprint.fetch("key")
      end

      def worker_class
        blueprint.dig("runtime", "handler")
      end

      def writer
        @writer ||= Marlon::Blueprint::FileWriter.new(root: root, force: force)
      end

      def planned_artifacts
        [
          artifact("compiled_manifest", "config/studio/generated/manifests/#{key}.json"),
          artifact("worker", "app/services/studio/workers/generated/#{key}.rb"),
          artifact("nevaeh_capabilities", "db/seeds/studio_generated/#{key}.rb"),
          artifact("gatekeeper_contract", "config/studio/generated/gatekeeper/#{key}.json"),
          artifact("pwa_contract", "config/studio/generated/pwa/#{key}.json"),
          artifact("input_schema", "config/studio/generated/schemas/#{key}.schema.json"),
          artifact("template", "config/studio/generated/templates/#{key}.json"),
          artifact("worker_test", "test/services/studio/workers/generated/#{key}_test.rb"),
          artifact("documentation", "docs/studio/blueprints/generated/#{key}.md")
        ]
      end

      def artifact(type, path)
        {"artifact_type" => type, "path" => path}
      end

      def content_for(type, artifacts)
        case type
        when "compiled_manifest"
          pretty_json(blueprint.merge("generated_artifacts" => artifacts))
        when "worker"
          worker_source
        when "nevaeh_capabilities"
          nevaeh_capabilities_source
        when "gatekeeper_contract"
          pretty_json(gatekeeper_contract)
        when "pwa_contract"
          pretty_json(pwa_contract)
        when "input_schema"
          pretty_json(input_schema)
        when "template"
          pretty_json(template_contract)
        when "worker_test"
          worker_test_source
        when "documentation"
          documentation_source
        else
          raise ArgumentError, "Unsupported generated artifact #{type.inspect}"
        end
      end

      def write_artifact(path, content, type)
        provenance = blueprint.fetch("provenance")
        writer.write(
          path,
          content,
          blueprint_key: "studio:#{key}",
          artifact_type: type,
          metadata: {
            "generated_by" => self.class.name,
            "studio_blueprint_key" => key,
            "studio_blueprint_source" => provenance.fetch("source"),
            "studio_blueprint_source_sha256" => provenance.fetch("source_sha256"),
            "studio_blueprint_compiler_version" => provenance.fetch("compiler_version"),
            "generated_path" => path
          }
        )
      end

      def worker_source
        actions = blueprint.fetch("actions").map { |item| item.fetch("name") }
        <<~RUBY
          # frozen_string_literal: true

          module Studio
            module Workers
              module Generated
                class #{key.camelize}
                  BLUEPRINT_KEY = #{key.inspect}
                  ACTIONS = #{actions.inspect}.freeze

                  def self.perform(action, payload = {})
                    action = action.to_s
                    unless ACTIONS.include?(action)
                      raise ArgumentError,
                            "Unsupported \#{BLUEPRINT_KEY} action: \#{action.inspect}"
                    end

                    Studio::Blueprint::Runtime.perform(
                      blueprint_key: BLUEPRINT_KEY,
                      action: action,
                      payload: payload
                    )
                  end
                end
              end
            end
          end
        RUBY
      end

      def nevaeh_capabilities_source
        definitions = blueprint.fetch("actions").map do |action|
          {
            "name" => "#{blueprint.fetch('name')} - #{action.fetch('name').humanize}",
            "slug" => action.fetch("capability"),
            "intent_name" => action.fetch("intent_name"),
            "description" => action.fetch("description"),
            "event_type" => action.fetch("event_type"),
            "intent_patterns" => action.fetch("intent_patterns"),
            "expected_outcome" => action.fetch("expected_outcome"),
            "realtime" => action.fetch("realtime"),
            "knowledge_article_ids" => action.fetch("knowledge_article_ids")
          }
        end

        <<~RUBY
          # frozen_string_literal: true

          definitions = #{definitions.inspect}

          definitions.each do |definition|
            capability = NevaehCapability.find_or_initialize_by(
              slug: definition.fetch("slug")
            )

            capability.assign_attributes(
              name: definition.fetch("name"),
              domain: "studio",
              description: definition.fetch("description"),
              intent_name: definition.fetch("intent_name"),
              subject_type: #{blueprint.dig("gatekeeper", "subject_type").inspect},
              handler: #{worker_class.inspect},
              queue: #{blueprint.dig("runtime", "queue").inspect},
              priority: #{blueprint.dig("runtime", "priority").inspect},
              gatekeeper_capability: definition.fetch("slug"),
              intent_patterns: definition.fetch("intent_patterns"),
              expected_outcome: definition.fetch("expected_outcome"),
              failure_policy: #{blueprint.dig("runtime", "failure_policy").inspect},
              realtime: definition.fetch("realtime"),
              input_adapter: {
                "studio_blueprint_key" => #{key.inspect},
                "schema_path" => #{input_schema_path.inspect}
              },
              metadata: {
                "generated" => true,
                "surface" => "studio_pwa",
                "studio_blueprint_key" => #{key.inspect},
                "provider" => #{blueprint.dig("runtime", "provider").inspect}
              },
              knowledge_article_ids: definition.fetch("knowledge_article_ids"),
              event_types: [definition.fetch("event_type")],
              enabled: #{blueprint.dig("runtime", "enabled").inspect}
            )

            capability.save!
          end

          puts "Generated Studio capabilities seeded (#{key}): \#{definitions.length}"
        RUBY
      end

      def gatekeeper_contract
        {
          "schema_version" => 1,
          "blueprint_key" => key,
          "policy" => blueprint.dig("gatekeeper", "policy"),
          "subject_type" => blueprint.dig("gatekeeper", "subject_type"),
          "provider" => blueprint.dig("runtime", "provider"),
          "enabled" => blueprint.dig("runtime", "enabled"),
          "capabilities" => blueprint.fetch("actions").map do |action|
            {
              "action" => action.fetch("name"),
              "capability" => action.fetch("capability")
            }
          end
        }
      end

      def pwa_contract
        {
          "schema_version" => 1,
          "blueprint_key" => key,
          "contract_type" => "studio_create_blueprint",
          "category" => blueprint.dig("pwa", "category"),
          "label" => blueprint.dig("pwa", "label"),
          "description" => blueprint.dig("pwa", "description"),
          "icon" => blueprint.dig("pwa", "icon"),
          "order" => blueprint.dig("pwa", "order"),
          "start_modes" => blueprint.dig("pwa", "start_modes"),
          "actions" => blueprint.fetch("actions").map do |action|
            action.slice("name", "capability", "intent_name", "description")
          end,
          "input_schema_path" => input_schema_path,
          "template_path" => template_path
        }
      end

      def input_schema
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$id" => "lightek://studio/blueprints/#{key}/input"
        }.merge(blueprint.fetch("inputs"))
      end

      def template_contract
        blueprint.fetch("template").merge(
          "schema_version" => 1,
          "blueprint_key" => key,
          "provider" => blueprint.dig("runtime", "provider")
        )
      end

      def worker_test_source
        actions = blueprint.fetch("actions").map { |item| item.fetch("name") }
        <<~RUBY
          # frozen_string_literal: true

          require "test_helper"

          module Studio
            module Workers
              module Generated
                class #{key.camelize}GeneratedTest < ActiveSupport::TestCase
                  test "declares generated Studio blueprint contract" do
                    assert_equal #{key.inspect}, #{key.camelize}::BLUEPRINT_KEY
                    assert_equal #{actions.inspect}, #{key.camelize}::ACTIONS
                  end
                end
              end
            end
          end
        RUBY
      end

      def documentation_source
        actions = blueprint.fetch("actions").map do |action|
          "- `#{action.fetch('name')}` -> `#{action.fetch('capability')}`"
        end.join("\n")

        modes = blueprint.dig("pwa", "start_modes")
        mode_lines =
          if modes.empty?
            "- None yet."
          else
            modes.map do |mode|
              "- **#{mode.fetch('label')}** (`#{mode.fetch('key')}`)"
            end.join("\n")
          end

        <<~MARKDOWN
          # #{blueprint.fetch("name")}

          Generated from Studio blueprint `#{key}`.

          #{blueprint.fetch("description")}

          ## Product law

          What should Marlon have to do to create something?

          Minimize that work. Backend complexity belongs to Lightek.

          ## Actions

          #{actions}

          ## PWA start modes

          #{mode_lines}

          ## Runtime

          - Worker: `#{worker_class}`
          - Provider: `#{blueprint.dig("runtime", "provider")}`
          - Enabled: `#{blueprint.dig("runtime", "enabled")}`
          - Execution handler: `#{blueprint.dig("runtime", "execution_handler") || "not configured"}`

          ## Provenance

          - Compiler: `#{blueprint.dig("provenance", "compiler")}`
          - Compiler version: `#{blueprint.dig("provenance", "compiler_version")}`
          - Source: `#{blueprint.dig("provenance", "source")}`
          - Source SHA-256: `#{blueprint.dig("provenance", "source_sha256")}`

          This document is generated. Change the canonical Studio blueprint and regenerate.
        MARKDOWN
      end

      def input_schema_path
        "config/studio/generated/schemas/#{key}.schema.json"
      end

      def template_path
        "config/studio/generated/templates/#{key}.json"
      end

      def pretty_json(value)
        JSON.pretty_generate(value) + "\n"
      end
    end
  end
end
