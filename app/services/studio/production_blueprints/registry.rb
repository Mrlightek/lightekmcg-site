# frozen_string_literal: true

# Production-architecture contract, not an executable creative generator.
# Nevaeh may resolve these plans; Gatekeeper must still authorize execution.
module Studio
  module ProductionBlueprints
    class Registry
      class UnsupportedIntent < ArgumentError; end
      class ClarificationRequired < ArgumentError; end

      VERSION = 1
      TYPES = {
        "film" => {
          "kind" => "film", "label" => "Feature Film",
          "departments" => %w[story script characters environments assets cinematography sound planning editorial delivery]
        },
        "scripted_series" => {
          "kind" => "series", "label" => "Scripted Series",
          "departments" => %w[series_bible story script characters environments assets cinematography sound planning editorial delivery]
        },
        "documentary" => {
          "kind" => "film", "label" => "Documentary",
          "departments" => %w[research interviews rights story script assets cinematography sound planning editorial delivery]
        },
        "music_video" => {
          "kind" => "film", "label" => "Music Video",
          "departments" => %w[treatment music rights choreography characters environments assets cinematography lighting editorial delivery]
        },
        "live_broadcast" => {
          "kind" => "live", "label" => "Live Broadcast",
          "departments" => %w[format rundown sources graphics assets lighting audio rehearsal transmission delivery]
        },
        "commercial" => {
          "kind" => "commercial", "label" => "Commercial",
          "departments" => %w[brief script storyboard characters assets environments lighting cinematography editorial delivery]
        },
        "standalone_asset" => {
          "kind" => nil, "label" => "Standalone Creative Asset",
          "departments" => %w[references asset_design asset_library review]
        }
      }.freeze

      # Explicitly modeled task dependencies. These are proposed jobs,
      # not a promise that a handler or queue already exists.
      COMMON_TASKS = [
        {"key" => "intent_review", "depends_on" => [], "output" => "approved_creation_contract"},
        {"key" => "asset_inventory", "depends_on" => ["intent_review"], "output" => "reuse_and_gap_manifest"},
        {"key" => "creative_brief", "depends_on" => ["intent_review"], "output" => "editable_creative_direction"},
        {"key" => "creative_outline", "depends_on" => ["creative_brief"], "output" => "editable_structure"},
        {"key" => "character_plan", "depends_on" => ["creative_outline", "asset_inventory"], "output" => "character_requirements"},
        {"key" => "environment_plan", "depends_on" => ["creative_outline", "asset_inventory"], "output" => "environment_requirements"},
        {"key" => "lighting_plan", "depends_on" => ["environment_plan"], "output" => "lighting_requirements"},
        {"key" => "script_draft", "depends_on" => ["creative_outline", "character_plan"], "output" => "editable_script_draft"},
        {"key" => "production_review", "depends_on" => ["lighting_plan", "script_draft"], "output" => "creator_review_packet"}
      ].freeze

      def self.keys = TYPES.keys

      def self.resolve!(intent_key:, production_type: nil)
        intent = intent_key.to_s.strip
        selected = production_type.to_s.strip
        if intent == "production"
          raise ClarificationRequired, "Choose the production type before creation" if selected.empty?
          raise UnsupportedIntent, "Unknown production type: #{selected}" unless TYPES.key?(selected) && selected != "standalone_asset"
          selected
        elsif %w[character environment prop vehicle architecture effect material].include?(intent)
          if selected.present? && selected != "standalone_asset"
            raise UnsupportedIntent, "Asset intent cannot be provisioned as #{selected}"
          end
          "standalone_asset"
        else
          raise ClarificationRequired, "Resolve the intended production blueprint before creation: #{intent}"
        end
      end

      def self.plan!(intent_key:, production_type: nil, start_mode_key:, name:)
        key = resolve!(intent_key: intent_key, production_type: production_type)
        name = name.to_s.strip
        start_mode = start_mode_key.to_s.strip
        raise ArgumentError, "Project name is required" if name.empty?
        raise ArgumentError, "Starting mode is required" if start_mode.empty?
        type = TYPES.fetch(key)
        tasks = key == "standalone_asset" ? [
          {"key" => "intent_review", "depends_on" => [], "output" => "approved_asset_contract"},
          {"key" => "asset_inventory", "depends_on" => ["intent_review"], "output" => "reuse_and_gap_manifest"},
          {"key" => "asset_design", "depends_on" => ["asset_inventory"], "output" => "editable_asset_definition"},
          {"key" => "asset_review", "depends_on" => ["asset_design"], "output" => "creator_review_packet"}
        ] : COMMON_TASKS
        {
          "schema_version" => VERSION,
          "blueprint_key" => key,
          "label" => type.fetch("label"),
          "production_kind" => type.fetch("kind"),
          "intent_key" => intent_key.to_s,
          "start_mode_key" => start_mode,
          "name" => name,
          "departments" => type.fetch("departments").dup,
          "tasks" => tasks.map { |task| task.transform_values { |value| value.is_a?(Array) ? value.dup : value } },
          "execution" => "not_dispatched",
          "authorization" => "required_before_execution",
          "creative_outputs" => "drafts_require_creator_review"
        }
      end
    end
  end
end
