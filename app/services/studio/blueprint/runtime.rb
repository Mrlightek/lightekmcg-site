# frozen_string_literal: true

module Studio
  module Blueprint
    class Runtime
      class BlueprintDisabled < StandardError; end
      class ExecutionNotConfigured < StandardError; end

      def self.perform(blueprint_key:, action:, payload: {})
        new(
          blueprint_key: blueprint_key,
          action: action,
          payload: payload
        ).perform
      end

      def initialize(blueprint_key:, action:, payload: {})
        @blueprint_key = blueprint_key.to_s
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
      end

      def perform
        ensure_action!
        ensure_enabled!
        handler_name = blueprint.dig("runtime", "execution_handler").presence

        unless handler_name
          raise ExecutionNotConfigured,
                "Studio blueprint #{blueprint_key.inspect} has no runtime.execution_handler"
        end

        handler = handler_name.constantize

        if handler.respond_to?(:perform)
          handler.perform(action, payload)
        elsif handler.respond_to?(:call)
          handler.call(action: action, payload: payload, blueprint: blueprint)
        else
          raise ExecutionNotConfigured,
                "#{handler_name} must respond to .perform or .call"
        end
      end

      private

      attr_reader :blueprint_key, :action, :payload

      def blueprint
        @blueprint ||= Studio::Blueprint::Compiler.call(source: blueprint_key)
      end

      def ensure_enabled!
        return if blueprint.dig(
          "runtime",
          "enabled"
        ) == true

        raise BlueprintDisabled,
              "Studio blueprint #{blueprint_key.inspect} is disabled"
      end

      def ensure_action!
        allowed = blueprint.fetch("actions").map { |item| item.fetch("name") }
        return if allowed.include?(action)

        raise ArgumentError,
              "Unsupported #{blueprint_key} Studio blueprint action #{action.inspect}; " \
              "expected #{allowed.join(', ')}"
      end
    end
  end
end
