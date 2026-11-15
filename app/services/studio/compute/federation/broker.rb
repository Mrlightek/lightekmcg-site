module Studio
  module Compute
    module Federation
      class Broker
        class Busy < ArgumentError; end
        FILES = {"movie.mp4" => "video", "scene.blend" => "blend", "preview.png" => "preview"}.freeze
        def self.authorize!(peer)
          allowed = ENV.fetch("STUDIO_CPU_REMOTE_PEERS", "").split(",").map(&:strip)
          raise ArgumentError, "Remote CPU service is not enabled for this installation" unless peer.reload.active? && allowed.include?(peer.key)
        end
        def self.submit!(peer:, request_key:, manifest:)
          authorize!(peer)
          raise ArgumentError, "Invalid remote render key" unless request_key.to_s.match?(/\A[0-9a-f]{48}\z/)
          snapshot = Contract.validate!(manifest)
          digest = Contract.digest(snapshot)
          row = nil
          peer.with_lock do
            row = StudioRemoteRender.find_by(peer: peer, request_key: request_key)
            if row
              raise ArgumentError, "Remote render key belongs to another snapshot" unless row.manifest_digest == digest
            else
              records = StudioRemoteRender.where(peer: peer)
              raise ArgumentError, "Remote CPU retention limit reached; contact the infrastructure operator" if records.count >= 100
              raise Busy, "This installation already has two queued or running remote renders" if records.joins(:studio_operation).where(studio_operations: {status: %w[pending running]}).count >= 2
              project = records.first&.studio_operation&.studio_project || StudioProject.create!(owner: peer.merchant, site: peer.site, name: "Remote CPU productions")
              operation = project.studio_operations.create!(provider: "blender", operation_type: "build_scene", capability: "studio.render.preview", status: "pending", intent: {user_id: peer.merchant_id}, manifest: snapshot)
              row = StudioRemoteRender.create!(peer: peer, studio_operation: operation, request_key: request_key, manifest_digest: digest)
            end
          end
          enqueue!(row)
          row
        end
        def self.status(row)
          authorize!(row.peer)
          Lease.reconcile!(StudioOperation.where(id: row.studio_operation_id))
          operation = row.studio_operation.reload
          if operation.status == "completed" && row.result.empty?
            row.with_lock do
              if row.result.empty?
                files = operation.artifacts.where(filename: FILES.keys).map do |artifact|
                  blob = artifact.file.blob
                  raise ArgumentError, "Remote output exceeds the 64 MiB transfer limit" if blob.byte_size > 64.megabytes
                  digest = Digest::SHA256.new
                  blob.download { |chunk| digest.update(chunk) }
                  {"filename" => artifact.filename, "bytes" => blob.byte_size, "sha256" => digest.hexdigest}
                end
                raise ArgumentError, "Remote renderer did not produce a movie" unless files.any? { |file| file["filename"] == "movie.mp4" }
                row.update!(result: {"files" => files})
              end
            end
          end
          {key: row.request_key, status: operation.status, progress: operation.metadata["cpu_render_progress"], files: operation.status == "completed" ? row.reload.result.fetch("files") : [], error: operation.status == "failed" ? "Remote CPU render failed; resume the saved attempt or contact the operator." : nil}
        end
        def self.resume!(row)
          authorize!(row.peer)
          Lease.reconcile!(StudioOperation.where(id: row.studio_operation_id))
          operation = row.studio_operation
          row.peer.with_lock do
            operation.with_lock do
              raise ArgumentError, "Cancelled remote renders cannot resume" if operation.status == "cancelled"
              if operation.status == "failed"
                active = StudioRemoteRender.where(peer: row.peer).joins(:studio_operation).where(studio_operations: {status: %w[pending running]}).count
                raise Busy, "This installation already has two queued or running remote renders" if active >= 2
                operation.update!(status: "pending", completed_at: nil, error_message: nil)
                row.update!(enqueued_at: nil)
              end
            end
          end
          enqueue!(row)
          row
        end
        def self.enqueue!(row)
          row.with_lock do
            if row.enqueued_at.nil? && row.studio_operation.reload.status == "pending"
              job = ExecuteStudioOperationJob.perform_later(row.studio_operation_id)
              raise "Remote CPU enqueue did not succeed" unless job && job.successfully_enqueued?
              row.update!(enqueued_at: Time.current)
            end
          end
        end
        def self.cancel!(row)
          authorize!(row.peer)
          row.studio_operation.with_lock do
            row.studio_operation.update!(status: "cancelled", completed_at: Time.current) unless %w[completed cancelled].include?(row.studio_operation.status)
          end
        end
      end
    end
  end
end
