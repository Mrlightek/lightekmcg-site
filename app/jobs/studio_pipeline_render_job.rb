# frozen_string_literal: true

class StudioPipelineRenderJob < ApplicationJob
  queue_as :studio

  def perform(id)
    operation = StudioOperation.find_by(id: id, capability: Studio::Pipeline::Render::CAPABILITY)
    return unless operation

    operation.with_lock do
      return unless operation.status == "pending"
      operation.update!(status: "running")
    end
    project = operation.studio_project
    access = Studio::Pipeline::Access.new(project.owner, project.site)
    runtime = Studio::Pipeline::Runtime
    Studio::MediaProcess.temporary_directory("pipeline-render-") do |root|
      operation.metadata.fetch("asset_blobs").each do |asset_id, blob_id|
        access.assets.find(asset_id)
        source = operation.layer_sources.attachments.find_by!(blob_id: blob_id)
        runtime.copy!(source, File.join(root, "asset-#{Integer(asset_id)}.glb"))
      end
      File.write(File.join(root, "scene.json"), JSON.generate(operation.manifest))
      runtime.blender!(root, "render_scene.py",
        ["--manifest", runtime.path(root, "scene.json"), "--out", runtime.path(root, "movie.mp4")], role: :render, timeout: 1800)
      verify!(root, operation)
      publish!(root, operation, access)
    end
  rescue StandardError => error
    Rails.logger.error("Studio pipeline render #{id}: #{error.class}: #{error.message}")
    operation&.with_lock do
      if operation.status == "running"
        detail = error.is_a?(Timeout::Error) ? "Rendering exceeded 30 minutes. Try a shorter shot or lower resolution." :
          "Blender could not complete this render. Try Cycles or check the worker and assets."
        operation.update!(status: "failed", error_message: detail)
      end
    end
  end

  private

  def verify!(root, operation)
    runtime = Studio::Pipeline::Runtime
    args = ["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
      "-show_entries", "stream=codec_name,width,height,avg_frame_rate,nb_read_frames", "-of", "json",
      runtime.path(root, "movie.mp4")]
    stream = JSON.parse(runtime.run!(root, args, role: :render, timeout: 90)).fetch("streams").fetch(0)
    manifest = operation.manifest
    frames = (manifest.fetch("durationSeconds") * manifest.fetch("fps")).round
    unless stream.values_at("codec_name", "width", "height", "avg_frame_rate", "nb_read_frames") ==
      ["h264", *manifest.fetch("resolution"), "#{manifest.fetch('fps')}/1", frames.to_s]
      raise ArgumentError, "Rendered video differs from the requested shot"
    end
  end

  def publish!(root, operation, access)
    filename = "pipeline-render-#{operation.id}.mp4"
    File.open(File.join(root, "movie.mp4"), "rb") do |io|
      blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: "video/mp4", identify: false)
      published = false
      operation.with_lock do
        if operation.status == "running"
          artifact = operation.artifacts.create!(kind: "video", filename: filename, metadata: {"content_type" => "video/mp4", "byte_size" => blob.byte_size})
          artifact.file.attach(blob)
          operation.update!(status: "completed")
          published = true
        end
      end
      unless published
        blob.purge_later
        return
      end
    end

    operation.metadata.fetch("asset_blobs").each do |asset_id, blob_id|
      asset = access.cards.find_by(id: asset_id, status: "ready")
      asset&.with_lock do
        if asset.proxy.blob&.id == blob_id
          asset.update!(metadata: asset.metadata.merge("pipeline_rendered_at" => Time.current.iso8601, "pipeline_render_id" => operation.id))
        end
      end
    end
  end
end
