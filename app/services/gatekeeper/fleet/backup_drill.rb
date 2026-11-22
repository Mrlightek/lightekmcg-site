# frozen_string_literal: true

module Gatekeeper
  module Fleet
    module BackupDrill
      CAPABILITY = "fleet.backup.restore_drill"
      module_function

      def queue!(actor:, target:)
        Rollouts.authorize!(actor)
        target.with_lock do
          installation = target.gatekeeper_installation
          raise Rollouts::Invalid, "An eligible Docker installation with a recorded update snapshot is required" unless
            installation.adapter == "docker_compose" && installation.eligible? && Recovery.receipt(target)["backup_recorded"]

          parameters = {"target_id" => target.id, "attempt" => target.attempts, "source_operation_id" => target.gatekeeper_operation_id,
            "actor_id" => actor.id}
          operation = GatekeeperOperation.find_by(gatekeeper_node: installation.gatekeeper_node,
            capability: CAPABILITY, parameters: parameters, status: %w[queued running succeeded])
          unless operation
            operation = GatekeeperOperation.create!(gatekeeper_node: installation.gatekeeper_node,
              gatekeeper_project: installation.gatekeeper_project, capability: CAPABILITY, parameters: parameters,
              requested_by: "user:#{actor.id}", status: "queued")
          end
          BackupDrillJob.perform_later(operation.id) if operation.status == "queued"
          {"operation_id" => operation.id, "target_id" => target.id, "status" => operation.status}
        end
      end

      def perform!(operation)
        payload = operation.with_lock do
          return unless operation.status == "queued"

          inputs = operation.parameters
          actor = User.find(inputs.fetch("actor_id"))
          raise Rollouts::Invalid, "Active Gatekeeper operator required" unless Hosting::Access.super_admin?(actor)
          target = GatekeeperUpdateTarget.find(inputs.fetch("target_id"))
          installation = target.gatekeeper_installation
          unless target.gatekeeper_operation_id == inputs["source_operation_id"] && target.attempts == inputs["attempt"] &&
              installation.gatekeeper_node_id == operation.gatekeeper_node_id && installation.adapter == "docker_compose" &&
              installation.eligible? && Recovery.receipt(target)["backup_recorded"]
            raise Rollouts::Invalid, "Snapshot or installation binding changed before the drill"
          end

          operation.update!(status: "running", started_at: Time.current)
          {"domain" => installation.domain, "target_id" => target.id, "attempt" => target.attempts}
        end
        result = Transport.run!(node: operation.gatekeeper_node, domain: payload.fetch("domain"), requested_by: operation.requested_by,
          operation_id: operation.id, payload: payload.dup, script_name: "verify_fleet_backup.py")
        unless result.slice(*payload.keys) == payload && result["status"] == "succeeded" && result["restored_schema"] == true
          raise Rollouts::Invalid, "The remote restore drill did not return matching schema evidence"
        end

        operation.update!(status: "succeeded", result: result, completed_at: Time.current, exit_status: 0)
      rescue StandardError => error
        operation.update!(status: "failed", error_class: error.class.name, error_message: "Restore drill did not complete",
          completed_at: Time.current, exit_status: 1)
        raise
      end
    end
  end
end
