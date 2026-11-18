require "socket"
require "fileutils"

module Studio
  module Compute
    class Lease
      class Lost < StandardError; end
      class Current < ActiveSupport::CurrentAttributes
        attribute :lease
      end
      TTL = Guardrails::LEASE_SECONDS.seconds

      def self.claim!(operation)
        pool = StudioComputePool.create_or_find_by!(name: "cpu")
        lease = nil
        pool.with_lock do
          operation.with_lock do
            return unless operation.executable?
            project = operation.studio_project
            tenant = project.site_id ? "site:#{project.site_id}" : "owner:#{project.owner_id}"
            limit = Integer(ENV.fetch("STUDIO_CPU_TENANT_SLOTS", "1"))
            raise ArgumentError, "CPU tenant slots must be 1–8" unless limit.between?(1, 8)
            raise CpuProfile::Busy if StudioComputeLease.active.where(tenant_key: tenant).count >= limit
            row = StudioComputeLease.find_or_initialize_by(studio_operation_id: operation.id)
            row.update!(tenant_key: tenant, token: SecureRandom.hex(24), worker: Socket.gethostname.first(120),
              expires_at: Time.current + TTL, released_at: nil)
            operation.update!(status: "running", started_at: Time.current, completed_at: nil, error_message: nil)
            lease = new(row, operation)
          end
        end
        lease
      end

      # Expiry exposes an interrupted attempt as failed; paid resume remains explicit.
      # No automatic charge or execution is created by reconciliation.
      def self.reconcile!(operations)
        StudioComputeLease.joins(:studio_operation).where(studio_operation_id: operations.select(:id))
          .where(studio_operations: {status: "running"}).where("expires_at <= ?", Time.current).find_each do |row|
          operation = row.studio_operation
          operation.with_lock do
            row.reload
            next if row.expires_at > Time.current
            operation.update!(status: "failed", completed_at: Time.current,
              error_message: "CPU worker stopped reporting. Resume this render to recover available saved frames.") if operation.status == "running"
            row.update!(released_at: Time.current)
          end
        end
      end

      def self.check! = Current.lease&.check!
      def self.heartbeat! = Current.lease&.heartbeat!

      def initialize(row, operation)
        @id, @token, @operation = row.id, row.token, operation
      end

      def valid? = owned.exists?

      def release!
        StudioComputeLease.where(id: @id, token: @token, released_at: nil).update_all(released_at: Time.current)
      end

      def check!
        raise Lost, "CPU render lease expired or was replaced" unless owned.exists?
        status = @operation.reload.status
        raise Studio::MediaProcess::Cancelled, "Operation cancelled by an application administrator" if status == "cancelled"
        raise Lost, "CPU render attempt is no longer running" unless status == "running"
      end

      def heartbeat!
        return if @heartbeat_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @heartbeat_at < 2
        raise Lost, "CPU render lease expired or was replaced" unless owned.update_all(expires_at: Time.current + TTL, updated_at: Time.current) == 1
        if (remote = StudioRemoteRender.find_by(studio_operation_id: @operation.id))
          Federation::Broker.authorize!(remote.peer)
        end
        @heartbeat_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        check!
      end

      def run
        # Shared POSIX workspace locking also protects checkpoints from a paused
        # old process after lease expiry. New work defers until it has exited.
        root = Pathname(ENV.fetch("BLENDER_OUTPUT_ROOT", Rails.root.join("storage/blender_jobs").to_s))
        FileUtils.mkdir_p(root.join(".locks"), mode: 0700)
        File.open(root.join(".locks", "operation-#{@operation.id}.lock"), File::RDWR | File::CREAT, 0600) do |file|
          raise CpuProfile::Busy unless file.flock(File::LOCK_EX | File::LOCK_NB)
          Current.set(lease: self) do
            check!
            yield
          end
        end
      end

      private

      def owned
        StudioComputeLease.where(id: @id, token: @token, released_at: nil).where("expires_at > ?", Time.current)
      end
    end
  end
end
