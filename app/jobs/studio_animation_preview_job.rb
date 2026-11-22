# frozen_string_literal: true

class StudioAnimationPreviewJob < ApplicationJob
  queue_as :studio

  def perform(asset_id, blob_id)
    asset = StudioAsset.animation_assets.find_by(id: asset_id)
    return unless asset && asset.file.blob.id == blob_id
    blob = asset.file.blob
    Studio::MediaProcess.temporary_directory("animation-preview-") do |root|
      FileUtils.mkdir_p(File.join(root, "inputs"))
      source = "inputs/#{blob.id}.#{blob.filename.extension.downcase}"
      File.open(File.join(root, source), "wb") { |file| blob.download { |chunk| file.write(chunk) } }
      FileUtils.cp(Rails.root.join(StudioSceneRenderJob::SCRIPT), File.join(root, "render.py"))
      File.write(File.join(root, "preview.json"), { version: 1, source: source }.to_json)
      args = %w[blender --background --factory-startup --disable-autoexec --threads 2 --python-exit-code 1 --python /work/render.py -- preview /work/preview.json]
      image = Studio::NativeBlender::Runtime.image(:render)
      Studio::MediaProcess.run!(Studio::MediaProcess.container(args, root: root, image: image), timeout: 120)
      asset.with_lock do
        return unless asset.file.blob.id == blob_id
        File.open(File.join(root, "preview.glb"), "rb") do |file|
          asset.proxy = { io: file, filename: "preview.glb", content_type: "model/gltf-binary", identify: false }
          asset.update!(metadata: asset.metadata.merge("animation_preview" => { "blob_id" => blob_id, "status" => "ready" }))
        end
      end
    end
  rescue StandardError => error
    Rails.logger.warn("Studio animation preview #{asset_id}: #{error.class}")
    asset&.with_lock do
      if asset.file.blob.id == blob_id
        asset.update!(metadata: asset.metadata.merge("animation_preview" => { "blob_id" => blob_id, "status" => "failed" }))
      end
    end
  end
end
