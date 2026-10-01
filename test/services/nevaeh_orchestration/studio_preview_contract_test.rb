# frozen_string_literal: true

require "test_helper"

class StudioPreviewContractTest < ActiveSupport::TestCase
  class CaptureEngine
    class << self
      attr_accessor :work_item

      def dispatch(item)
        self.work_item = item
        item
      end
    end
  end

  setup do
    @original_engine =
      DymondDispatch::EngineAdapter.engine

    DymondDispatch::EngineAdapter.engine =
      CaptureEngine

    CaptureEngine.work_item = nil

    @capability =
      NevaehCapability.find_or_create_by!(
        slug: "studio.preview"
      ) do |capability|
        capability.name = "Studio Preview"
        capability.domain = "studio"
        capability.intent_name = "preview_scene"
        capability.handler = "Studio::Workers::Preview"
        capability.queue = "media"
        capability.priority = 5
        capability.gatekeeper_capability = "studio.preview"
        capability.event_types = ["studio.preview.requested"]
        capability.expected_outcome = {
          "artifact_kind" => "preview"
        }
        capability.failure_policy = {
          "retries" => 2,
          "escalate" => true
        }
        capability.realtime = {
          "stream_template" => "studio:scene:{subject_id}",
          "include_result" => true
        }
        capability.enabled = true
      end

    @capability.update!(
      handler: "Studio::Workers::Preview",
      event_types: ["studio.preview.requested"],
      expected_outcome: {
        "artifact_kind" => "preview"
      },
      realtime: {
        "stream_template" => "studio:scene:{subject_id}",
        "include_result" => true
      },
      enabled: true
    )

    @studio_project =
      StudioProject.create!(
        name: "QA Studio Project"
      )

    @production =
      Production.create!(
        studio_project: @studio_project,
        name: "QA Production",
        kind: "general",
        status: "development",
        metadata: {}
      )

    @scene =
      StudioScene.create!(
        studio_project: @studio_project,
        production: @production,
        name: "QA Scene"
      )
  end

  teardown do
    DymondDispatch::EngineAdapter.engine =
      @original_engine

    if defined?(@work_item) && @work_item
      @work_item.destroy!
    end

    if defined?(@operation) && @operation
      @operation.destroy!
    end

    @scene&.destroy!
    @production&.destroy!
    @studio_project&.destroy!
  end

  test "studio preview resolves authorizes and dispatches the real preview worker" do
    scene = @scene

    correlation_id =
      NevaehOrchestration::Correlation.generate

    @operation =
      Studio::Operations::Create.build_scene!(
        scene: scene,
        requested_by: "contract_test",
        intent: {
          "purpose" => "studio_preview"
        }
      )

    metadata =
      @operation.metadata.to_h.deep_dup

    @operation.update!(
      status: "pending",
      metadata:
        metadata.merge(
          "billing" => {
            "required" => false,
            "reason" => "studio_preview"
          },
          "orchestration" => {
            "managed_by" => "nevaeh",
            "correlation_id" => correlation_id,
            "authorized" => false
          }
        )
    )

    result =
      Nevaeh.handle(
        event_type: "studio.preview.requested",
        source: "dymond_studio",
        subject: scene,
        payload: {
          "scene_id" => scene.id,
          "operation_id" => @operation.id
        },
        context: {
          "production_id" => scene.production_id,
          "scene_id" => scene.id,
          "operation_id" => @operation.id
        },
        args: [
          @operation.id,
          correlation_id
        ],
        correlation_id: correlation_id
      )

    @work_item = result.work_item

    assert_equal "studio.preview", result.capability.slug
    assert_equal "preview_scene", result.intent.name
    assert result.authorized?
    assert result.dispatched?

    assert_equal(
      "Studio::Workers::Preview",
      @work_item.handler
    )

    assert_equal(
      @operation.id,
      Array(@work_item.args).first
    )

    assert_equal(
      correlation_id,
      Array(@work_item.args).second
    )

    correlations = [
      correlation_id,
      @operation.metadata.dig(
        "orchestration",
        "correlation_id"
      ),
      result.event.correlation_id,
      result.intent.correlation_id,
      result.plan.correlation_id,
      result.authorization.correlation_id,
      @work_item.correlation_id
    ]

    assert_equal(
      1,
      correlations.compact.uniq.length
    )

    assert_equal(
      @work_item,
      CaptureEngine.work_item
    )

    broadcast =
      Array(@work_item.dispositions).find do |spec|
        spec["kind"] == "broadcast"
      end

    assert_not_nil broadcast

    assert_equal(
      "studio:scene:#{scene.id}",
      broadcast["stream"]
    )

    assert_equal(
      true,
      broadcast["include_result"]
    )
  end

  test "studio preview capability requires a preview artifact outcome" do
    correlation_id =
      NevaehOrchestration::Correlation.generate

    plan =
      @capability.build_plan(
        correlation_id: correlation_id
      )

    good =
      NevaehOrchestration::Outcome.new(
        status: "succeeded",
        result: {
          "artifact_kind" => "preview",
          "artifact_id" => 123
        },
        correlation_id: correlation_id
      )

    bad =
      NevaehOrchestration::Outcome.new(
        status: "succeeded",
        result: {
          "artifact_kind" => "manifest"
        },
        correlation_id: correlation_id
      )

    assert(
      NevaehOrchestration::Evaluator
        .call(
          plan: plan,
          outcome: good
        )
        .complete?
    )

    assert(
      NevaehOrchestration::Evaluator
        .call(
          plan: plan,
          outcome: bad
        )
        .escalate?
    )
  end
end
