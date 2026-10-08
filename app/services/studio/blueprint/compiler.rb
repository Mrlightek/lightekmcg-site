# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module Studio
  module Blueprint
    class Compiler
      SCHEMA_VERSION = 1
      COMPILER_VERSION = 1
      KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/
      CAPABILITY_PATTERN = /\Astudio\.[a-z0-9_.]+\z/

      class InvalidBlueprint < StandardError; end

      def self.call(source:, root: Rails.root)
        new(source: source, root: root).call
      end

      def initialize(source:, root: Rails.root)
        @source = source
        @root = Pathname(root)
      end

      def call
        definition = load_definition
        validate_source!(definition)
        compiled = normalize(definition)
        validate_compiled!(compiled)
        compiled
      end

      private

      attr_reader :source, :root

      def load_definition
        value = source.is_a?(Hash) ? source : JSON.parse(resolved_source_path.read)
        value.to_h.deep_stringify_keys
      rescue JSON::ParserError => e
        raise InvalidBlueprint, "Studio blueprint JSON is invalid: #{e.message}"
      end

      def resolved_source_path
        @resolved_source_path ||= begin
          value = source.to_s
          path =
            if value.end_with?(".json") || value.include?("/")
              candidate = Pathname(value)
              candidate.absolute? ? candidate : root.join(candidate)
            else
              root.join("config", "studio", "blueprints", "#{value}.json")
            end
          raise InvalidBlueprint, "Studio blueprint source not found: #{path}" unless path.file?
          path
        end
      end

      def validate_source!(definition)
        invalid!("schema_version must be 1") unless integer_value(definition["schema_version"]) == 1
        invalid!("key is invalid") unless KEY_PATTERN.match?(definition["key"].to_s)
        invalid!("name is required") if definition["name"].to_s.strip.empty?
        actions = Array(definition["actions"])
        invalid!("at least one action is required") if actions.empty?
        actions.each_with_index do |action, index|
          name = action.to_h.deep_stringify_keys["name"].to_s
          invalid!("actions[#{index}].name is invalid") unless KEY_PATTERN.match?(name)
        end
      end

      def normalize(definition)
        key = definition.fetch("key").to_s
        name = definition.fetch("name").to_s.strip
        description = definition["description"].to_s.strip
        runtime_source = definition.fetch("runtime", {}).to_h.deep_stringify_keys
        pwa_source = definition.fetch("pwa", {}).to_h.deep_stringify_keys
        gatekeeper_source = definition.fetch("gatekeeper", {}).to_h.deep_stringify_keys
        template_source = definition.fetch("template", {}).to_h.deep_stringify_keys

        {
          "schema_version" => SCHEMA_VERSION,
          "key" => key,
          "name" => name,
          "description" => description,
          "actions" => Array(definition["actions"]).map { |item| normalize_action(key, item) },
          "runtime" => {
            "handler" => runtime_source["handler"].presence || "Studio::Workers::Generated::#{key.camelize}",
            "execution_handler" => runtime_source["execution_handler"].presence,
            "queue" => runtime_source["queue"].presence || "default",
            "priority" => integer_value(runtime_source.fetch("priority", 5)),
            "enabled" => runtime_source["enabled"] == true,
            "provider" => runtime_source["provider"].presence || "blender",
            "failure_policy" => {"retries" => 1, "escalate" => true}.merge(
              runtime_source.fetch("failure_policy", {}).to_h.deep_stringify_keys
            )
          },
          "gatekeeper" => gatekeeper_source.merge(
            "policy" => gatekeeper_source["policy"].presence || "registered_enabled_capability",
            "subject_type" => gatekeeper_source["subject_type"].presence
          ),
          "pwa" => pwa_source.merge(
            "category" => pwa_source["category"].presence || key,
            "label" => pwa_source["label"].presence || name,
            "description" => pwa_source["description"].presence || description,
            "icon" => pwa_source["icon"].presence || "sparkles",
            "order" => integer_value(pwa_source.fetch("order", 100)),
            "start_modes" => Array(pwa_source["start_modes"]).map { |mode| normalize_mode(mode) }
          ),
          "inputs" => {
            "type" => "object",
            "properties" => {},
            "required" => [],
            "additionalProperties" => true
          }.merge(definition.fetch("inputs", {}).to_h.deep_stringify_keys),
          "template" => template_source.merge(
            "key" => template_source["key"].presence || "#{key}_default",
            "name" => template_source["name"].presence || "#{name} Default",
            "kind" => template_source["kind"].presence || key,
            "defaults" => template_source.fetch("defaults", {}).to_h.deep_stringify_keys
          ),
          "metadata" => definition.fetch("metadata", {}).to_h.deep_stringify_keys,
          "provenance" => {
            "compiler" => self.class.name,
            "compiler_version" => COMPILER_VERSION,
            "source" => source_label,
            "source_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonicalize(definition)))
          }
        }
      end

      def normalize_action(key, action)
        item = action.to_h.deep_stringify_keys
        name = item.fetch("name").to_s
        capability = item["capability"].presence || "studio.#{key}.#{name}"
        {
          "name" => name,
          "capability" => capability,
          "intent_name" => item["intent_name"].presence || "#{name}_studio_#{key}",
          "event_type" => item["event_type"].presence || "#{capability}.requested",
          "description" => item["description"].presence || "#{name.humanize} #{key.humanize} in Lightek Studio.",
          "intent_patterns" => Array(item["intent_patterns"]),
          "expected_outcome" => item.fetch("expected_outcome", {"blueprint_key" => key, "action" => name}).to_h.deep_stringify_keys,
          "realtime" => item.fetch("realtime", {}).to_h.deep_stringify_keys,
          "knowledge_article_ids" => Array(item["knowledge_article_ids"])
        }
      end

      def normalize_mode(mode)
        item = mode.respond_to?(:to_h) ? mode.to_h.deep_stringify_keys : {"key" => mode.to_s}
        key = item["key"].to_s
        {
          "key" => key,
          "label" => item["label"].presence || key.humanize,
          "description" => item["description"].to_s,
          "input_defaults" => item.fetch("input_defaults", {}).to_h.deep_stringify_keys
        }
      end

      def validate_compiled!(compiled)
        actions = compiled.fetch("actions")
        duplicate_names = duplicates(actions.map { |a| a.fetch("name") })
        duplicate_caps = duplicates(actions.map { |a| a.fetch("capability") })
        invalid!("duplicate action names: #{duplicate_names.join(', ')}") if duplicate_names.any?
        invalid!("duplicate capabilities: #{duplicate_caps.join(', ')}") if duplicate_caps.any?
        actions.each do |action|
          cap = action.fetch("capability")
          invalid!("invalid capability #{cap.inspect}") unless CAPABILITY_PATTERN.match?(cap)
        end
        priority = compiled.dig("runtime", "priority")
        invalid!("runtime.priority must be 0..10") unless priority.is_a?(Integer) && priority.between?(0, 10)
        invalid!("pwa.order must be an integer") unless compiled.dig("pwa", "order").is_a?(Integer)
        invalid!("inputs.type must be object") unless compiled.dig("inputs", "type") == "object"
        modes = compiled.dig("pwa", "start_modes")
        modes.each { |mode| invalid!("invalid PWA start mode") unless KEY_PATTERN.match?(mode.fetch("key")) }
        duplicate_modes = duplicates(modes.map { |mode| mode.fetch("key") })
        invalid!("duplicate PWA start modes: #{duplicate_modes.join(', ')}") if duplicate_modes.any?
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.map(&:to_s).uniq.sort.to_h do |key|
            source_value =
              if value.key?(key)
                value[key]
              elsif value.key?(key.to_sym)
                value[key.to_sym]
              end
            [key, canonicalize(source_value)]
          end
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end

      def source_label
        return "inline" if source.is_a?(Hash)
        resolved_source_path.relative_path_from(root).to_s
      rescue ArgumentError
        resolved_source_path.to_s
      end

      def integer_value(value)
        Integer(value, exception: false)
      end

      def duplicates(values)
        values.tally.select { |_value, count| count > 1 }.keys
      end

      def invalid!(message)
        raise InvalidBlueprint, "Invalid Studio blueprint: #{message}"
      end
    end
  end
end
