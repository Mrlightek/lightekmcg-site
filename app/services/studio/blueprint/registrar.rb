# frozen_string_literal: true

module Studio
  module Blueprint
    # Turns generated feature actions into live, queryable Nevaeh capabilities.
    # Registration is idempotent; publication is not the same as permission to run.
    class Registrar
      def self.call(blueprint:)
        new(blueprint).call
      end

      def initialize(blueprint)
        @blueprint = blueprint.to_h.deep_stringify_keys
      end

      def call
        NevaehCapability.transaction do
          blueprint.fetch("actions").map { |action| register!(action) }
        end
      end

      private

      attr_reader :blueprint

      def executable?
        blueprint.fetch("status") == "published" &&
          blueprint.dig("runtime", "enabled") == true &&
          blueprint.dig("runtime", "execution_handler").present?
      end

      def register!(action)
        slug = action.fetch("capability")
        record = NevaehCapability.find_or_initialize_by(slug: slug)
        # Do not hijack a manually managed or another feature's capability.
        if record.persisted? && record.metadata.to_h["studio_blueprint_key"] != blueprint.fetch("key")
          raise ArgumentError, "Capability #{slug} is not owned by this blueprint"
        end
        record.assign_attributes(
          name: "#{blueprint.fetch('name')} - #{action.fetch('name').humanize}",
          domain: "studio",
          description: action.fetch("description"),
          intent_name: action.fetch("intent_name"),
          subject_type: blueprint.dig("gatekeeper", "subject_type"),
          handler: blueprint.dig("runtime", "handler"),
          queue: blueprint.dig("execution", "queue"),
          priority: blueprint.dig("runtime", "priority"),
          gatekeeper_capability: slug,
          intent_patterns: action.fetch("intent_patterns"),
          expected_outcome: action.fetch("expected_outcome"),
          failure_policy: blueprint.dig("runtime", "failure_policy"),
          realtime: action.fetch("realtime"),
          input_adapter: {
            "studio_blueprint_key" => blueprint.fetch("key"),
            "schema_path" => "config/studio/generated/schemas/#{blueprint.fetch('key')}.schema.json"
          },
          metadata: {
            "generated" => true,
            "surface" => "studio_pwa",
            "studio_blueprint_key" => blueprint.fetch("key"),
            "blueprint_version" => blueprint.fetch("version"),
            "blueprint_status" => blueprint.fetch("status"),
            "source_sha256" => blueprint.dig("provenance", "source_sha256"),
            "execution_handler" => blueprint.dig("runtime", "execution_handler"),
            "intent" => blueprint.fetch("intent"),
            "plan" => blueprint.fetch("plan"),
            "execution" => blueprint.fetch("execution"),
            "outputs" => blueprint.fetch("outputs"),
            "review" => blueprint.fetch("review"),
            "execution_ready" => executable?
          },
          knowledge_article_ids: action.fetch("knowledge_article_ids"),
          event_types: [action.fetch("event_type")],
          enabled: executable?
        )
        record.save!
        Studio::Blueprint::IntelligenceSync.call(blueprint: blueprint, action: action, capability: record)
        record
      end
    end
  end
end
