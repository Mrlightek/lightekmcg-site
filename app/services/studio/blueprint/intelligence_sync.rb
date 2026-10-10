# frozen_string_literal: true

module Studio
  module Blueprint
    # Called from Registrar's transaction, so capability and intelligence
    # registrations are atomic. Runtime code is never evaluated here.
    class IntelligenceSync
      def self.call(blueprint:, action:, capability:)
        new(blueprint: blueprint, action: action, capability: capability).call
      end

      def initialize(blueprint:, action:, capability:)
        @blueprint = blueprint.to_h.deep_stringify_keys
        @action = action.to_h.deep_stringify_keys
        @capability = capability
      end

      def call
        intent_key = action.fetch("capability")
        record = NevaehIntelligence.find_or_initialize_by(intent_key: intent_key)
        existing_owner = record.metadata.to_h["studio_blueprint_key"]
        if record.persisted? && existing_owner != blueprint.fetch("key")
          raise ArgumentError, "Intelligence #{intent_key} belongs to another owner"
        end

        record.assign_attributes(
          name: "#{blueprint.fetch('name')} - #{action.fetch('name').humanize}",
          operation: NevaehIntelligence::OPERATIONS.include?(action.fetch("name")) ? action.fetch("name") : "execute",
          target_model: blueprint.dig("metadata", "target_model"),
          nevaeh_capability: capability,
          status: status,
          execution_mode: blueprint.dig("execution", "mode") == "sync" ? "sync" : "async",
          instructions: {
            "action" => action.fetch("name"),
            "event_type" => action.fetch("event_type"),
            "blueprint_key" => blueprint.fetch("key"),
            "inputs" => blueprint.fetch("inputs"),
            "expected_outcome" => action.fetch("expected_outcome")
          },
          metadata: {
            "generated" => true,
            "studio_blueprint_key" => blueprint.fetch("key"),
            "blueprint_version" => blueprint.fetch("version"),
            "source_sha256" => blueprint.dig("provenance", "source_sha256"),
            "execution_ready" => handler_ready?
          }
        )
        record.save!
        record
      end

      private

      attr_reader :blueprint, :action, :capability

      def status
        case blueprint.fetch("status")
        when "archived" then "archived"
        when "published"
          capability.enabled? && handler_ready? ? "published" : "draft"
        else "draft"
        end
      end

      def handler_ready?
        return false unless blueprint.dig("runtime", "enabled") == true
        name = blueprint.dig("runtime", "execution_handler").to_s
        return false if name.empty?
        handler = name.safe_constantize
        handler && (handler.respond_to?(:perform) || handler.respond_to?(:call))
      end
    end
  end
end
