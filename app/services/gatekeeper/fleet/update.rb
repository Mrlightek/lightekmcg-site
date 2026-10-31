module Gatekeeper
  module Fleet
    class Update
      def self.call!(target)
        rollout = target.gatekeeper_rollout
        operation = nil
        rollout.with_lock do
          target.reload
          return unless rollout.status == "running" && target.status == "queued"
          installation = target.gatekeeper_installation
          operation = GatekeeperOperation.create!(gatekeeper_node: installation.gatekeeper_node,
            capability: "update_installation", requested_by: rollout.requested_by,
            parameters: {target_id: target.id, installation_id: installation.id, release_id: rollout.gatekeeper_release_id},
            status: "running", started_at: Time.current)
          target.update!(status: "running", attempts: target.attempts + 1, started_at: Time.current,
            completed_at: nil, gatekeeper_operation: operation,
            previous_version: installation.current_version, previous_image: installation.current_image)
        end
        installation = target.gatekeeper_installation
        raise Rollouts::Invalid, "Installation is no longer eligible" unless installation.eligible?
        receipt = Transport.call!(target)
        release = rollout.gatekeeper_release
        raise Rollouts::Invalid, "Remote version verification failed" unless receipt["status"] == "succeeded" &&
          receipt["domain"] == installation.domain && receipt["source_sha"] == release.source_sha && receipt["image"] == release.image
        rollout.with_lock do
          # A stale worker must not overwrite a later attempt's result.
          target.reload
          return unless target.status == "running" && target.gatekeeper_operation_id == operation.id
          installation.update!(current_version: release.source_sha, current_image: release.image, last_verified_at: Time.current)
          operation.update!(status: "succeeded", exit_status: 0, result: receipt, completed_at: Time.current)
          target.update!(status: "succeeded", receipt: receipt, completed_at: Time.current, error_message: nil)
        end
      rescue StandardError => error
        raise unless operation
        safe = "Update failed (#{error.class.name}); inspect operation ##{operation.id} and the remote update receipt."
        failed_receipt = error.is_a?(Transport::RemoteFailure) ? error.receipt : {}
        operation.update!(status: "failed", exit_status: 1, error_class: error.class.name,
          error_message: safe, result: failed_receipt, completed_at: Time.current)
        rollout.with_lock do
          target.reload
          if target.status == "running" && target.gatekeeper_operation_id == operation.id
            target.update!(status: "failed", error_message: safe, receipt: failed_receipt, completed_at: Time.current)
            rollout.update!(status: "paused", message: safe) unless rollout.status == "canceled"
          end
        end
        begin
          safe_error = RuntimeError.new(safe)
          knowledge = Gatekeeper::KnowledgeService.find_for_failure(operation: operation, error: safe_error)
          ticket = Gatekeeper::SupportTicketService.open_for_failure!(operation: operation, error: safe_error, knowledge_articles: knowledge)
          operation.update!(result: operation.result.to_h.merge(support_ticket_id: ticket.id, support_ticket_number: ticket.number))
        rescue StandardError => escalation_error
          Rails.logger.error("[Fleet] operation=#{operation.id} ticket escalation failed: #{escalation_error.class}")
        end
      ensure
        DispatchJob.perform_later(rollout.id) if operation && rollout
      end
    end
  end
end
