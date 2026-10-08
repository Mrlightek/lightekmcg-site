# frozen_string_literal: true

module NevaehOrchestration
  module Workers
    class SelfKnowledge
      ACTIONS = %w[
        summary
        history
        runtime_state
        learning_model
        observability
      ].freeze

      def self.perform(
        action,
        payload = {}
      )
        new(
          action:
            action,

          payload:
            payload
        ).perform
      end

      def initialize(
        action:,
        payload:
      )
        @action =
          action.to_s

        @payload =
          payload
            .to_h
            .deep_stringify_keys
      end

      def perform
        unless ACTIONS.include?(
          action
        )
          raise ArgumentError,
                "Unsupported Nevaeh self-knowledge action: #{action.inspect}"
        end

        case action
        when "summary"
          NevaehOrchestration::SelfKnowledge.snapshot

        when "history"
          NevaehOrchestration::SelfKnowledge.history(
            limit:
              payload.fetch(
                "limit",
                25
              )
          )

        when "runtime_state"
          NevaehOrchestration::SelfKnowledge.runtime_state(
            recent_limit:
              payload.fetch(
                "recent_limit",
                10
              )
          )

        when "learning_model"
          NevaehOrchestration::SelfKnowledge.learning_model

        when "observability"
          NevaehOrchestration::SelfKnowledge.observability_contract
        end
      end

      private

      attr_reader \
        :action,
        :payload
    end
  end
end
