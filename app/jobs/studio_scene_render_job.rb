# frozen_string_literal: true

class StudioSceneRenderJob < ApplicationJob
  queue_as :studio

  SCRIPT = "lib/scripts/studio_scene_render.py"
  RENDER_TIMEOUT = 20.minutes

  def perform(id, watchdog: false)
    render = StudioSceneRender.find_by(id: id)
    return unless render
    if watchdog
      render.with_lock do
        fail_render(render, "The video worker was interrupted. Submit a new render.") if render.active?
      end
      return
    end

    render.with_lock do
      return unless render.status == "queued"
      self.class.set(wait: RENDER_TIMEOUT + 5.minutes).perform_later(id, watchdog: true)
      render.update!(status: "preparing", progress: 2)
    end
    Studio::MediaProcess.temporary_directory("scene-render-") { |root| export(render, Pathname.new(root)) }
  rescue StandardError => error
    # Worker diagnostics can contain paths or user-authored media metadata.
    Rails.logger.error("Studio scene render #{id}: #{error.class}")
    render&.with_lock do
      fail_render(render, "Video rendering failed during #{render.status}. Check the input formats and render worker, then submit a new render.") if render.active?
    end
  end

  private

  def export(render, root)
    FileUtils.mkdir_p(root.join("inputs"))
    render.inputs.blobs.each do |blob|
      target = root.join("inputs", "#{blob.id}.#{blob.filename.extension.to_s.downcase}")
      File.open(target, "wb") { |file| blob.download { |chunk| file.write(chunk) } }
    end
    File.write(root.join("manifest.json"), JSON.generate(render.manifest))
    FileUtils.cp(Rails.root.join(SCRIPT), root.join("render.py"))
    render.update!(status: "rendering", progress: 5)
    args = %w[blender --background --factory-startup --disable-autoexec --threads 2 --python-exit-code 1 --python /work/render.py -- render /work/manifest.json]
    run(args, root, timeout: RENDER_TIMEOUT.to_i, on_tick: -> { update_frames(render, root) })
    render.update!(status: "encoding", progress: 92)
    run(%w[python3 /work/render.py encode /work/manifest.json], root, timeout: 120)
    output = root.join("scene.mp4")
    raise "Missing video output" unless output.file? && output.size.positive?
    output.open("rb") do |file|
      # Upload before publishing the completed status. Active Storage attaches an
      # existing blob inside this transaction and never exposes a partial output.
      blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: "scene-#{render.id}.mp4", content_type: "video/mp4", identify: false)
      render.with_lock do
        if render.status == "encoding"
          render.video = blob
          render.update!(status: "completed", progress: 100)
        else
          blob.purge_later
        end
      end
    end
  end

  def update_frames(render, root)
    frame = root.join("progress").read.to_i
    progress = [5 + 85 * frame / render.manifest.fetch("frame_count"), 90].min
    render.update!(progress: progress) if progress > render.progress
  rescue Errno::ENOENT
    nil
  end

  def run(args, root, **options)
    image = Studio::NativeBlender::Runtime.image(:render)
    Studio::MediaProcess.run!(Studio::MediaProcess.container(args, root: root, image: image), **options)
  end

  def fail_render(render, message)
    render.update!(status: "failed", error_message: message)
  end
end
