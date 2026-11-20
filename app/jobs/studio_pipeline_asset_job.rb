# frozen_string_literal: true

class StudioPipelineAssetJob < ApplicationJob
  queue_as :studio

  def perform(id, version)
    asset = StudioAsset.find_by(id: id)
    return unless asset

    asset.with_lock do
      return unless asset.metadata["pipeline_version"] == version && asset.status == "uploaded" && !asset.metadata["pipeline_prepared"]
      asset.update!(status: "processing")
    end
    Studio::Pipeline::Access.new(User.find(asset.metadata.fetch("pipeline_actor")), asset.site).cards.find(asset.id)
    Studio::MediaProcess.temporary_directory("pipeline-ingest-") do |root|
      bundle = "source"
      source = File.join(bundle, asset.metadata.fetch("pipeline_source_name"))
      Studio::Pipeline::Runtime.copy!(asset.file, File.join(root, source))
      asset.pipeline_sidecars.each do |attachment|
        index = Integer(attachment.filename.base, 10)
        relative = Studio::Pipeline::Intake.relative_path(asset.metadata.fetch("pipeline_sidecar_paths").fetch(index))
        Studio::Pipeline::Runtime.copy!(attachment, File.join(root, bundle, relative))
      end
      if File.extname(source).downcase == ".unitypackage"
        options = asset.metadata["pipeline_model_path"].present? ? ["--model-path", asset.metadata["pipeline_model_path"]] : []
        source = Studio::MediaProcess.run!(["python3", Rails.root.join("script/media_pipeline/scripts/unpack_unity.py").to_s,
          File.join(root, source), File.join(root, "unity"), *options], timeout: 60).strip
        source = File.join("unity", Studio::Pipeline::Intake.relative_path(source))
        bundle = "unity"
      end

      base = asset.metadata["pipeline_stage"] == "base"
      output = base ? "mixamo.fbx" : "asset.glb"
      runtime = Studio::Pipeline::Runtime
      args = ["--input", runtime.path(root, source), "--bundle", runtime.path(root, bundle),
        "--out", runtime.path(root, "asset.glb")]
      args.concat(["--mixamo-out", runtime.path(root, output)]) if base
      runtime.blender!(root, "bpy_normalize.py", args, role: :asset, timeout: 240)
      publish!(asset, version, File.join(root, output), base)
    end
  rescue StandardError => error
    Rails.logger.error("Studio pipeline ingest #{id}: #{error.class}: #{error.message}")
    asset&.with_lock do
      if asset.metadata["pipeline_version"] == version && asset.status == "processing"
        message = error.message.to_s.lines.find { |line| line.include?("Unity package:") || line.include?("normalize:") }
        asset.update!(status: "failed", error_message: message&.strip&.first(500) || "Conversion failed. Check the export and try again.")
      end
    end
  end

  private

  def publish!(asset, version, path, base)
    clips = base ? [] : Studio::Pipeline::Render.glb_clips(path)
    File.open(path, "rb") do |io|
      blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: File.basename(path),
        content_type: base ? "application/octet-stream" : "model/gltf-binary", identify: false)
      applied = false
      asset.with_lock do
        if asset.metadata["pipeline_version"] == version && asset.status == "processing"
          if base
            asset.pipeline_base.attach(blob)
          else
            asset.proxy.attach(blob)
          end
          asset.update!(status: base ? "uploaded" : "ready", error_message: nil,
            metadata: asset.metadata.merge("pipeline_stage" => base ? "base" : "ready", "pipeline_prepared" => base,
              "pipeline_clips" => clips).except("pipeline_rendered_at"))
          applied = true
        end
      end
      blob.purge_later unless applied
    end
  end
end
