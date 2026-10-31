module Gatekeeper
  module Fleet
    class Rollouts
      class Invalid < StandardError; end

      def self.authorize!(actor)
        raise Invalid, "Super administrator access is required" unless actor&.persisted? && actor.role == "super_admin"
      end

      def self.create!(release:, installations:, requested_by:, **options)
        ids = installations.map(&:id).uniq.sort
        raise Invalid, "Select at least one installation" if ids.empty?
        GatekeeperRollout.transaction do
          rollout = GatekeeperRollout.create!(gatekeeper_release: release, requested_by: requested_by, **options)
          GatekeeperInstallation.where(id: ids).includes(:gatekeeper_node).order(:id).each_with_index do |installation, index|
            raise Invalid, "Installation #{installation.domain} is unavailable, pinned, or does not match this release" unless installation.accepts_release?(release)
            rollout.gatekeeper_update_targets.create!(gatekeeper_installation: installation,
              canary: index < rollout.canary_size, previous_version: installation.current_version,
              previous_image: installation.current_image)
          end
          rollout
        end
      end

      def self.start!(rollout)
        rollout.with_lock do
          raise Invalid, "Only draft rollouts can start" unless rollout.status == "draft"
          # Reserve the complete snapshot, including future batches, to prevent an
          # older concurrent rollout from downgrading a customer after a newer one.
          targets = rollout.gatekeeper_update_targets.includes(gatekeeper_installation: :gatekeeper_node)
          targets.each do |target|
            installation = target.gatekeeper_installation
            raise Invalid, "Installation #{installation.domain} no longer accepts this release" unless installation.accepts_release?(rollout.gatekeeper_release)
            target.update!(status: "reserved")
          end
          rollout.update!(status: "running", message: nil)
        end
        Gatekeeper::Fleet::DispatchJob.perform_later(rollout.id)
      rescue ActiveRecord::RecordNotUnique
        raise Invalid, "A selected installation already has an active rollout"
      end

      def self.control!(rollout, action)
        rollout.with_lock do
          case action
          when "pause"
            raise Invalid, "Rollout is not running" unless rollout.status == "running"
            rollout.update!(status: "paused", message: "Paused by operator; in-flight updates finish.")
          when "resume", "retry"
            raise Invalid, "Pause or complete the canary before resuming" unless %w[paused canary_ready].include?(rollout.status)
            raise Invalid, "Wait for in-flight updates to finish" if rollout.gatekeeper_update_targets.where(status: "running").exists?
            failed = rollout.gatekeeper_update_targets.where(status: "failed")
            raise Invalid, "Retry failed installations before continuing" if failed.exists? && action != "retry"
            failed.update_all(status: "reserved", error_message: nil, started_at: nil) if action == "retry"
            rollout.update!(status: "running", promoted: rollout.promoted? || rollout.status == "canary_ready", message: nil)
          when "cancel"
            raise Invalid, "Rollout has already finished" if %w[completed canceled].include?(rollout.status)
            rollout.gatekeeper_update_targets.where(status: %w[pending reserved queued failed]).update_all(status: "canceled")
            rollout.update!(status: "canceled", message: "Canceled by operator; in-flight updates finish.")
          else
            raise Invalid, "Unknown rollout action"
          end
        end
        Gatekeeper::Fleet::DispatchJob.perform_later(rollout.id) if rollout.status == "running"
      rescue ActiveRecord::RecordNotUnique
        raise Invalid, "Another rollout now owns a selected installation"
      end

      def self.dispatch!(rollout)
        rollout.with_lock do
          return unless rollout.status == "running" && (!rollout.scheduled_at || rollout.scheduled_at <= Time.current)
          targets = rollout.gatekeeper_update_targets
          return if targets.where(status: %w[queued running]).exists?
          if targets.where(status: "failed").exists?
            rollout.update!(status: "paused", message: "An update failed. Inspect its operation and retry.")
          elsif !targets.where(status: "reserved").exists?
            rollout.update!(status: "completed", message: "Every selected installation passed version and health checks.")
          elsif !rollout.promoted? && targets.where(canary: true, status: "reserved").none?
            if rollout.auto_promote?
              rollout.update!(promoted: true)
              queue_batch!(rollout, targets.where(status: "reserved").order(:id).limit(rollout.batch_size))
            else
              rollout.update!(status: "canary_ready", message: "Canary passed. Promote to update remaining customers.")
            end
          else
            scope = targets.where(status: "reserved").order(:id)
            scope = scope.where(canary: true) unless rollout.promoted?
            queue_batch!(rollout, scope.limit(rollout.promoted? ? rollout.batch_size : rollout.canary_size))
          end
        end
      end

      def self.queue_batch!(rollout, targets)
        targets.each { |target| target.update!(status: "queued") }
        # Enqueue only after transaction commit. The sweep recovers a lost enqueue.
      end
    end
  end
end
