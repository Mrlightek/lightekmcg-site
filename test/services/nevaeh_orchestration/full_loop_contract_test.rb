# frozen_string_literal: true

require "test_helper"

class NevaehFullLoopContractTest < ActiveSupport::TestCase
  class TestEngine
    class << self
      attr_accessor :dispatched

      def dispatch(work_item)
        self.dispatched = work_item
        work_item
      end
    end
  end

  setup do
    @original_engine =
      DymondDispatch::EngineAdapter.engine

    DymondDispatch::EngineAdapter.engine =
      TestEngine

    TestEngine.dispatched = nil

    @capability =
      NevaehCapability.create!(
        name: "QA Preview",
        slug: unique_slug,
        domain: "qa",
        description: "Contract-test capability.",

        intent_name: "qa_preview",

        handler: "QA::Workers::Preview",
        queue: "default",
        priority: 5,

        gatekeeper_capability: unique_slug,

        event_types: [
          unique_event_type
        ],

        expected_outcome: {
          "artifact_kind" => "preview"
        },

        failure_policy: {
          "retries" => 2,
          "escalate" => true
        },

        realtime: {
          "stream_template" => "qa:{subject_id}",
          "include_result" => true
        },

        input_adapter: {
          "type" => "contract_test"
        },

        enabled: true
      )
  end

  teardown do
    DymondDispatch::EngineAdapter.engine =
      @original_engine

    DymondDispatch::WorkItem
      .where(kind: @capability&.slug)
      .delete_all

    @capability&.destroy!
  end

  test "public facade resolves intent authorizes and dispatches one correlated request" do
    result =
      Nevaeh.handle(
        event_type: unique_event_type,
        source: "contract_test",
        payload: {
          "fixture" => true
        }
      )

    assert_instance_of(
      NevaehOrchestration::RequestResult,
      result
    )

    assert_equal(
      unique_event_type,
      result.event.event_type
    )

    assert_equal(
      "qa_preview",
      result.intent.name
    )

    assert_equal(
      @capability,
      result.capability
    )

    assert result.authorized?
    assert result.dispatched?

    assert_equal(
      @capability.slug,
      result.work_item.kind
    )

    assert_equal(
      "QA::Workers::Preview",
      result.work_item.handler
    )

    correlation_ids = [
      result.event.correlation_id,
      result.intent.correlation_id,
      result.plan.correlation_id,
      result.authorization.correlation_id,
      result.work_item.correlation_id
    ]

    assert_equal(
      1,
      correlation_ids.compact.uniq.length,
      "correlation ID must remain identical through the entire orchestration path"
    )

    assert_equal(
      result.work_item,
      TestEngine.dispatched
    )
  end

  test "request result is completely inspectable" do
    result =
      Nevaeh.handle(
        event_type: unique_event_type,
        source: "contract_test"
      )

    inspected = result.to_h

    assert_equal(
      result.correlation_id,
      inspected[:correlation_id]
    )

    assert_equal(
      unique_event_type,
      inspected.dig(:event, :event_type)
    )

    assert_equal(
      "qa_preview",
      inspected.dig(:intent, :name)
    )

    assert_equal(
      @capability.slug,
      inspected.dig(:capability, :slug)
    )

    assert_equal(
      true,
      inspected.dig(:authorization, :allowed)
    )

    assert_equal(
      result.work_item.id,
      inspected.dig(:work_item, :id)
    )
  end

  test "evaluator accepts a result only when expected outcome is satisfied" do
    correlation =
      NevaehOrchestration::Correlation.generate

    plan =
      @capability.build_plan(
        correlation_id: correlation
      )

    correct =
      NevaehOrchestration::Outcome.new(
        status: "succeeded",
        result: {
          "artifact_kind" => "preview"
        },
        correlation_id: correlation
      )

    correct_decision =
      NevaehOrchestration::Evaluator.call(
        plan: plan,
        outcome: correct
      )

    assert correct_decision.complete?

    wrong =
      NevaehOrchestration::Outcome.new(
        status: "succeeded",
        result: {
          "artifact_kind" => "manifest"
        },
        correlation_id: correlation,
        metadata: {
          "attempts" => 2
        }
      )

    wrong_decision =
      NevaehOrchestration::Evaluator.call(
        plan: plan,
        outcome: wrong
      )

    assert wrong_decision.escalate?
  end

  test "failure retries before escalation" do
    correlation =
      NevaehOrchestration::Correlation.generate

    plan =
      @capability.build_plan(
        correlation_id: correlation
      )

    first_failure =
      NevaehOrchestration::Outcome.new(
        status: "failed",
        error_class: "QAError",
        error_message: "temporary",
        correlation_id: correlation,
        metadata: {
          "attempts" => 0
        }
      )

    first_decision =
      NevaehOrchestration::Evaluator.call(
        plan: plan,
        outcome: first_failure
      )

    assert first_decision.retry?

    exhausted_failure =
      NevaehOrchestration::Outcome.new(
        status: "failed",
        error_class: "QAError",
        error_message: "still broken",
        correlation_id: correlation,
        metadata: {
          "attempts" => 2
        }
      )

    exhausted_decision =
      NevaehOrchestration::Evaluator.call(
        plan: plan,
        outcome: exhausted_failure
      )

    assert exhausted_decision.escalate?
  end

  test "gatekeeper denies an incompatible subject contract" do
    @capability.update!(
      subject_type: "StudioScene"
    )

    decision =
      Gatekeeper::AuthorizationService.call(
        capability:
          @capability.gatekeeper_capability,
        subject: Object.new,
        context: {
          correlation_id:
            NevaehOrchestration::Correlation.generate
        }
      )

    assert decision.denied?
    assert_match(
      /Subject type/,
      decision.reason
    )
  end

  private

  def unique_token
    @unique_token ||=
      "#{Process.pid}_#{object_id}"
  end

  def unique_slug
    "qa.preview.#{unique_token}"
  end

  def unique_event_type
    "qa.preview.#{unique_token}.requested"
  end
end
