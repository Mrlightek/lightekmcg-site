# frozen_string_literal: true

require "test_helper"

module NevaehOrchestration
  class SelfKnowledgeTest < ActiveSupport::TestCase
    test "runtime context carries durable identity learning and lineage" do
      context =
        SelfKnowledge.runtime_context

      assert_equal(
        "Nevaeh",
        context.fetch(
          "name"
        )
      )

      assert context.fetch(
        "self_model_version"
      ).present?

      assert_equal(
        "Knowledge-backed operational learning",
        context.fetch(
          "learning_model"
        )
      )

      assert_equal(
        "No silent transmission states.",
        context.fetch(
          "observability_law"
        )
      )

      history =
        context.fetch(
          "development_history"
        )

      assert history.fetch(
        "snapshot_id"
      ).present?

      assert history.fetch(
        "source_head"
      ).present?

      assert_operator(
        history.fetch(
          "repository_commit_count"
        ),
        :>,
        0
      )
    end

    test "learning model records trouble-ticket feedback into knowledge" do
      learning =
        SelfKnowledge.learning_model

      steps =
        learning.fetch(
          "steps"
        )

      assert steps.any? {
        |step|
        step.include?(
          "trouble ticket"
        )
      }

      assert steps.any? {
        |step|
        step.include?(
          "validated"
        )
      }

      assert steps.any? {
        |step|
        step.include?(
          "durable knowledge"
        )
      }
    end

    test "observability contract forbids silent transmission states" do
      contract =
        SelfKnowledge.observability_contract

      assert_equal(
        "No silent transmission states.",
        contract.fetch(
          "law"
        )
      )

      assert_includes(
        contract.fetch(
          "required_progress_fields"
        ),
        "percent"
      )

      assert_includes(
        contract.fetch(
          "distributed_work_fields"
        ),
        "correlation_id"
      )
    end

    test "runtime state reads live operational state from the database" do
      state =
        RuntimeState.snapshot(
          recent_limit:
            2
        )

      assert_equal(
        "database",
        state.fetch(
          "source"
        )
      )

      assert state.fetch(
        "network"
      ).key?(
        "enabled_ports"
      )

      assert state.fetch(
        "dispatch"
      ).key?(
        "by_status"
      )

      assert state.fetch(
        "gatekeeper"
      ).key?(
        "by_status"
      )

      assert state.fetch(
        "tickets"
      ).key?(
        "by_status"
      )

      assert state.fetch(
        "capabilities"
      ).key?(
        "enabled"
      )

      assert state.fetch(
        "recent"
      ).key?(
        "dispatch_work_items"
      )
    end

    test "self knowledge worker exposes summary history learning and observability" do
      summary =
        Workers::SelfKnowledge.perform(
          "summary"
        )

      assert_equal(
        "Nevaeh",
        summary.dig(
          "identity",
          "name"
        )
      )

      history =
        Workers::SelfKnowledge.perform(
          "history",
          {
            limit:
              3
          }
        )

      assert_operator(
        history.fetch(
          "returned"
        ),
        :<=,
        3
      )

      runtime =
        Workers::SelfKnowledge.perform(
          "runtime_state",
          {
            recent_limit:
              1
          }
        )

      assert_equal(
        "database",
        runtime.fetch(
          "source"
        )
      )

      assert_equal(
        "Knowledge-backed operational learning",
        Workers::SelfKnowledge
          .perform(
            "learning_model"
          )
          .fetch(
            "name"
          )
      )

      assert_equal(
        "No silent transmission states.",
        Workers::SelfKnowledge
          .perform(
            "observability"
          )
          .fetch(
            "law"
          )
      )
    end
  end
end
