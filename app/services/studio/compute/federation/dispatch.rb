module Studio
  module Compute
    module Federation
      class Dispatch
        def self.enabled?(operation)
          receipt = operation.metadata["remote_cpu"].is_a?(Hash)
          mode = operation.metadata["cpu_routing_mode"]
          remote = receipt || mode == "remote" || (mode.nil? && ENV["STUDIO_CPU_REMOTE"] == "1")
          remote && Queue.economy?(operation) && !StudioRemoteRender.exists?(studio_operation_id: operation.id)
        end
        def self.client(operation) = LightekReservations::Federation::Client.new(operation.studio_project.site)
        def self.cancel!(operation)
          receipt = operation.metadata["remote_cpu"]
          if receipt && receipt["connection"]
            config = LightekReservations::Federation::Client.config(operation.studio_project.site)
            raise ArgumentError, "Remote CPU connection changed; reconcile cancellation with the original operator" unless config && receipt["connection"] == Contract.digest(config.slice("origin", "key", "credential_slug"))
          end
          client(operation).request("studio/cpu/#{receipt.fetch('key')}/cancel", method: :post, body: {}) if receipt
        end
        def self.call(operation)
          raise ArgumentError, "Remote CPU requires a successfully paid final movie" unless operation.paid? && !operation.metadata["draft_preview"]
          snapshot = Contract.validate!(operation.manifest)
          Studio::Gatekeeper::Client.authorize!(capability: operation.capability, subject: operation, context: {project_id: operation.studio_project_id, provider: "remote_cpu"})
          config = LightekReservations::Federation::Client.config(operation.studio_project.site) || raise(ArgumentError, "This installation is not connected to the Lightek network")
          connection_id = Contract.digest(config.slice("origin", "key", "credential_slug"))
          receipt = operation.metadata["remote_cpu"]
          raise ArgumentError, "Remote CPU connection changed; reconcile the existing render before rerouting" if receipt && receipt["connection"] && receipt["connection"] != connection_id
          operation.with_lock do
            Lease.check!
            unless receipt
              receipt = {"key" => SecureRandom.hex(24), "status" => "submitting", "connection" => connection_id}
              operation.update!(metadata: operation.metadata.merge("remote_cpu" => receipt))
            end
          end
          connection = client(operation)
          # Repeating submission is safe even after a lost first response.
          data = connection.request("studio/cpu", method: :post, body: {key: receipt.fetch("key"), manifest: snapshot})
          if (receipt["status"] == "failed" || receipt["resume_requested"]) && data["status"] == "failed"
            data = connection.request("studio/cpu/#{receipt.fetch('key')}/resume", method: :post, body: {})
          end
          raise ArgumentError, "Remote CPU receipt did not match this render" unless data["key"] == receipt["key"] && %w[pending running completed failed cancelled].include?(data["status"])
          if data["status"] == "completed"
            files = data.fetch("files")
            raise ArgumentError, "Invalid remote CPU output receipt" unless files.is_a?(Array) && files.length.between?(1, 3) && files.map { |file| file["filename"] }.uniq.length == files.length && files.any? { |file| file["filename"] == "movie.mp4" }
            Studio::MediaProcess.temporary_directory("remote-cpu-") do |root|
              files.each do |file|
                filename = file.fetch("filename")
                kind = Broker::FILES[filename] || raise(ArgumentError, "Unexpected remote output")
                raise ArgumentError, "Invalid remote output size or checksum" unless file["bytes"].is_a?(Integer) && file["bytes"].between?(1, 64.megabytes) && file["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
                path = File.join(root, filename)
                observed = File.open(path, "wb") { |io| connection.download_cpu_file(key: receipt.fetch("key"), filename: filename, io: io) }
                raise ArgumentError, "Remote output checksum did not match" unless observed == file.slice("bytes", "sha256")
                File.open(path, "rb") do |io|
                  operation.with_lock do
                    Lease.check!
                    artifact = operation.artifacts.find_or_initialize_by(filename: filename, kind: kind)
                    content_type = {"video" => "video/mp4", "preview" => "image/png", "blend" => "application/octet-stream"}.fetch(kind)
                    artifact.file.attach(io: io, filename: filename, content_type: content_type, identify: false)
                    artifact.save!
                  end
                end
              end
            end
          end
          operation.with_lock do
            Lease.check!
            metadata = operation.metadata.merge("remote_cpu" => {"key" => receipt.fetch("key"), "status" => data.fetch("status"), "connection" => connection_id})
            progress = data["progress"]
            metadata["cpu_render_progress"] = operation.metadata.fetch("cpu_render_progress", {}).merge("profile" => "cpu_economy", "phase" => "remote_#{data.fetch('status')}") unless progress.is_a?(Hash)
            metadata["cpu_render_progress"] = progress.slice("profile", "phase", "completed_frames", "total_frames", "reused_frames", "elapsed_seconds", "cpu_seconds", "blender_peak_rss_bytes", "worker_elapsed_seconds") if progress.is_a?(Hash)
            terminal = %w[completed failed cancelled].include?(data["status"])
            operation.update!(status: terminal ? data["status"] : "pending", metadata: metadata,
              completed_at: terminal ? Time.current : nil, error_message: data["status"] == "failed" ? "Remote CPU render failed. Resume the saved attempt without another checkout." : nil)
          end
          !%w[pending running].include?(data["status"])
        rescue LightekReservations::Federation::Client::CpuBusy
          operation.with_lock do
            Lease.check!
            progress = operation.metadata.fetch("cpu_render_progress", {}).merge("profile" => "cpu_economy", "phase" => "waiting_for_remote_capacity")
            operation.update!(status: "pending", error_message: nil, metadata: operation.metadata.merge("cpu_render_progress" => progress))
          end
          false
        end
      end
    end
  end
end
