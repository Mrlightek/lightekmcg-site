# frozen_string_literal: true

module Studio
  module Workers
    class Preview
      def self.perform(studio_operation_id, correlation_id = nil)
        new(
          studio_operation_id: studio_operation_id,
          correlation_id: correlation_id
        ).perform
      end

      def initialize(studio_operation_id:, correlation_id: nil)
        @studio_operation_id = studio_operation_id
        @correlation_id = correlation_id
      end

      def perform
        operation =
          StudioOperation.find(studio_operation_id)

        prepare_operation_for_execution!(operation)

        ExecuteStudioOperationJob.perform_now(operation.id)

        operation.reload

        unless operation.status == "completed"
          raise(
            "Studio preview operation ##{operation.id} finished with " \
            "status #{operation.status.inspect}"
          )
        end

        artifact =
          operation.artifacts.find_by(kind: "preview")

        unless artifact
          raise(
            "Studio preview operation ##{operation.id} completed without " \
            "a preview artifact"
          )
        end

        {
          "artifact_kind" => "preview",
          "artifact_id" => artifact.id,
          "operation_id" => operation.id,
          "scene_id" => operation.studio_scene_id,
          "status" => operation.status
        }
      end

      private

      attr_reader :studio_operation_id, :correlation_id

      def prepare_operation_for_execution!(operation)
        metadata =
          operation.metadata.to_h.deep_dup

        orchestration =
          metadata
            .fetch("orchestration", {})
            .merge(
              "managed_by" => "nevaeh",
              "authorized" => true,
              "correlation_id" =>
                correlation_id.presence ||
                metadata.dig(
                  "orchestration",
                  "correlation_id"
                )
            )

        attributes = {
          metadata:
            metadata.merge(
              "orchestration" => orchestration.compact
            ),
          error_message: nil
        }

        if operation.status.in?(%w[failed cancelled])
          attributes[:status] = "pending"
          attributes[:completed_at] = nil
        end

        operation.update!(attributes)
      end
    end
  end
end
