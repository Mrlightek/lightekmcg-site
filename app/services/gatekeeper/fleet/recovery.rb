# frozen_string_literal: true

module Gatekeeper
  module Fleet
    module Recovery
      module_function

      def rollback!(target:, actor:)
        Rollouts.authorize!(actor)
        installation = target.gatekeeper_installation
        installation.with_lock do
          target.reload
          current_release = target.gatekeeper_rollout.gatekeeper_release
          unless target.status == "succeeded" && target.gatekeeper_operation&.status == "succeeded" &&
              matching_attempt?(target, target.gatekeeper_operation, target.receipt.to_h) &&
              installation.current_version == current_release.source_sha && installation.current_image == current_release.image &&
              installation.gatekeeper_update_targets.where(status: "succeeded").order(completed_at: :desc, id: :desc).first&.id == target.id
            raise Rollouts::Invalid, "Choose the latest verified update for this installation"
          end
          raise Rollouts::Invalid, "The deployed release is not marked compatible with its previous schema" unless current_release.backward_compatible?
          raise Rollouts::Invalid, "This update did not change the release" if
            [target.previous_version, target.previous_image] == [installation.current_version, installation.current_image]

          candidates = GatekeeperRelease.where(source_sha: target.previous_version, image: target.previous_image,
            adapter: installation.adapter, component: installation.component, channel: installation.channel)
          previous = candidates.order(:id).find { |candidate| installation.accepts_release?(candidate) }
          raise Rollouts::Invalid, "The previous release is not registered or permitted by installation policy" unless previous

          rollout = Rollouts.create!(release: previous, installations: [installation], requested_by: "user:#{actor.id}",
            canary_size: 1, batch_size: 1)
          Rollouts.start!(rollout)
          rollout
        end
      end

      def receipt(target)
        saved = target.receipt.to_h
        operation = target.gatekeeper_operation
        bound = operation && matching_attempt?(target, operation, saved)
        {
          "target_id" => target.id,
          "rollout_id" => target.gatekeeper_rollout_id,
          "status" => target.status,
          "operation_id" => operation&.id,
          "previous_release_verified" => !!(bound && operation.status == "failed" &&
            saved["code_restored"] == true && saved["previous_version"] == target.previous_version),
          "backup_recorded" => !!(bound && saved["database_backup"].present?)
        }
      end

      def matching_attempt?(target, operation, saved)
        installation = target.gatekeeper_installation
        release = target.gatekeeper_rollout.gatekeeper_release
        operation.capability == "update_installation" && operation.gatekeeper_node_id == installation.gatekeeper_node_id &&
          operation.parameters.to_h.values_at("target_id", "installation_id", "release_id") == [target.id, installation.id, release.id] &&
          saved.values_at("domain", "source_sha", "image", "target_id", "attempt") ==
            [installation.domain, release.source_sha, release.image, target.id, target.attempts]
      end
    end
  end
end
