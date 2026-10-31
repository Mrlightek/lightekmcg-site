module Gatekeeper
  module Fleet
    class Releases
      def self.register!(attributes)
        payload = attributes.stringify_keys
        payload["created_by"] = "github_release_pipeline"
        payload["channel"] ||= "stable"
        payload["adapter"] ||= "native_rails"
        payload["component"] ||= "lightek_app"
        payload["repository"] ||= Adapters::MAIN_REPOSITORY
        payload["image"] = nil if payload["image"].blank?
        payload["backward_compatible"] = !!ActiveModel::Type::Boolean.new.cast(payload.fetch("backward_compatible", false))
        release = find_or_register!(payload)
        raise Rollouts::Invalid, "Release version already identifies another artifact" unless release.attributes.slice(*payload.keys) == payload
        if automatic? && current_source?(release)
          release.with_lock do
            unless release.gatekeeper_rollouts.exists?
              installations = GatekeeperInstallation.where(enabled: true, automatic_updates: true, channel: release.channel).includes(:gatekeeper_node).select { |installation| installation.accepts_release?(release) }
              unless installations.empty?
                Rollouts.create!(release: release, installations: installations,
                  requested_by: "github_release_pipeline", canary_size: 1, batch_size: 10,
                  auto_promote: ENV["LIGHTEK_FLEET_AUTO_PROMOTE"] == "true")
              end
            end
          end
          release.gatekeeper_rollouts.where(status: "draft", requested_by: "github_release_pipeline").each { |rollout| start_pending!(rollout) }
        end
        release
      end

      def self.automatic? = ENV["LIGHTEK_FLEET_AUTO_ROLLOUT"] == "true"

      def self.find_or_register!(payload)
        GatekeeperRelease.find_by(version: payload.fetch("version")) || GatekeeperRelease.create!(payload)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Model uniqueness validation can win before the database constraint.
        existing = GatekeeperRelease.find_by(version: payload.fetch("version"))
        raise unless existing
        existing
      end

      def self.current_source?(release)
        # Other service repositories can register releases, but never inherit the
        # main application's automatic fan-out policy.
        release.component == "lightek_app" && Adapters.repository_key(release.repository) == Adapters.repository_key(Adapters::MAIN_REPOSITORY) &&
          GatekeeperProject.find_by(name: "lightekmcg-site")&.deployed_sha == release.source_sha
      end

      def self.start_pending!(rollout)
        return unless automatic?
        rollout.with_lock do
          return unless rollout.status == "draft"
          unless current_source?(rollout.gatekeeper_release)
            Rollouts.control!(rollout, "cancel")
            return
          end
          ids = rollout.gatekeeper_update_targets.select(:gatekeeper_installation_id)
          return if GatekeeperUpdateTarget.where(gatekeeper_installation_id: ids, status: %w[reserved queued running failed]).exists?
          Rollouts.start!(rollout)
        end
      rescue Rollouts::Invalid
        # An overlapping rollout or an installation policy change can occur
        # between the read and reservation. Preserve the reviewable draft.
        nil
      end
    end
  end
end
