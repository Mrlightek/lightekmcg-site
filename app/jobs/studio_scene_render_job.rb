# frozen_string_literal: true

class StudioSceneRenderJob < ApplicationJob
  queue_as :studio

  SCRIPT = "lib/scripts/studio_scene_render.py"
  RENDER_TIMEOUT = 20.minutes
  HEARTBEAT_INTERVAL = 15.seconds
  FAILURE_MESSAGES = {
    "preparing" => "Could not prepare the saved inputs. Retry this render, or replace unavailable assets and render the scene again.",
    "rendering" => "Blender could not render the saved scene. Retry this render, or check the scene and assets before rendering again.",
    "encoding" => "Could not encode or store the MP4. Retry this render from the saved snapshot."
  }.freeze

  def perform(id, watchdog: false)
    # Delayed watchdogs from before the lease rollout can still be in Sidekiq.
    return if watchdog
    render = StudioSceneRender.find_by(id: id)
    token = render&.claim!
    return unless token

    Studio::MediaProcess.temporary_directory("scene-render-") do |root|
      export(render, token, Pathname.new(root))
    end
  rescue StudioSceneRender::ClaimLost, ActiveRecord::RecordNotFound
    # The sweep or another attempt owns the outcome.
  rescue StandardError => error
    Rails.logger.error("Studio scene render #{id}: #{error.class}")
    return unless token
    begin
      render.with_claim!(token, StudioSceneRender::RUNNING_STATUSES) do
        message = if error.is_a?(Timeout::Error)
          "The worker timed out while #{render.status}. Retry this render from the saved snapshot."
        elsif error.is_a?(Studio::MediaProcess::BlenderCapacity) || error.is_a?(Studio::Compute::CpuProfile::Busy)
          error.message
        else
          FAILURE_MESSAGES.fetch(render.status)
        end
        render.mark_failed!(message)
      end
    rescue StudioSceneRender::ClaimLost, ActiveRecord::RecordNotFound
      # Leave an expired or finished attempt alone.
    end
  end

  private

  def export(render, token, root)
    prepare = heartbeat(render, token, "preparing")
    FileUtils.mkdir_p(root.join("inputs"))
    render.inputs.blobs.each do |blob|
      target = root.join("inputs", "#{blob.id}.#{blob.filename.extension.to_s.downcase}")
      File.open(target, "wb") do |file|
        blob.download do |chunk|
          prepare.call
          file.write(chunk)
        end
      end
    end
    File.write(root.join("manifest.json"), JSON.generate(render.manifest))
    FileUtils.cp(Rails.root.join(SCRIPT), root.join("render.py"))
    render.advance_claim!(token, "preparing", status: "rendering", progress: 5)
    args = %w[blender --background --factory-startup --disable-autoexec --threads 2 --python-exit-code 1 --python /work/render.py -- render /work/manifest.json]
    run(args, root, timeout: RENDER_TIMEOUT.to_i, on_tick: heartbeat(render, token, "rendering", root))
    render.advance_claim!(token, "rendering", status: "encoding", progress: 92)
    run(%w[python3 /work/render.py encode /work/manifest.json], root, timeout: 120,
      on_tick: heartbeat(render, token, "encoding"))
    publish(render, token, root.join("scene.mp4"))
  end

  def heartbeat(render, token, phase, root = nil)
    next_heartbeat = 0
    lambda do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if now < next_heartbeat
      render.with_claim!(token, phase) do |time|
        attributes = { lease_expires_at: time + StudioSceneRender::LEASE_DURATION }
        if root
          frame = read_frame(root)
          progress = [5 + 85 * frame / render.manifest.fetch("frame_count"), 90].min
          attributes[:progress] = [render.progress, progress].max
        end
        render.update!(attributes)
      end
      next_heartbeat = now + HEARTBEAT_INTERVAL
    end
  end

  def read_frame(root)
    root.join("progress").read.to_i
  rescue Errno::ENOENT
    0
  end

  def publish(render, token, output)
    blob = nil
    published = false
    render.advance_claim!(token, "encoding")
    raise "Missing video output" unless output.file? && output.size.positive?
    output.open("rb") do |file|
      blob = ActiveStorage::Blob.build_after_unfurling(io: file, filename: "scene-#{render.id}.mp4",
        content_type: "video/mp4", identify: false)
      blob.save!
      blob.upload_without_unfurling(file)
      render.with_claim!(token, "encoding") do
        render.video = blob
        render.update!(status: "completed", progress: 100, claim_token: nil, lease_expires_at: nil)
      end
      published = true
    end
  ensure
    blob.purge_later if blob&.persisted? && !published
  end

  def run(args, root, **options)
    image = Studio::NativeBlender::Runtime.image(:render)
    Studio::MediaProcess.run!(Studio::MediaProcess.container(args, root: root, image: image), **options)
  end
end
