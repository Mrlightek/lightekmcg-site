# frozen_string_literal: true

class StudioAnimationPreviewJob < ApplicationJob
  queue_as :studio

  def perform(preview_id, token)
    preview = StudioAnimationPreview.find_by(id: preview_id, attempt_token: token, status: "queued")
    return unless preview
    asset = preview.studio_asset
    return unless asset.native_animation_model? && asset.animation_source.blob.id == preview.settings.fetch("blob_id")
    blob = asset.animation_source.blob

    Studio::MediaProcess.temporary_directory("animation-preview-") do |root|
      FileUtils.mkdir_p(File.join(root, "inputs"))
      source = "inputs/#{blob.id}.#{blob.filename.extension.downcase}"
      File.open(File.join(root, source), "wb") { |file| blob.download { |chunk| file.write(chunk) } }
      FileUtils.cp(Rails.root.join(StudioSceneRenderJob::SCRIPT), File.join(root, "render.py"))
      manifest = preview.settings.except("blob_id").merge(version: 1, source: source)
      File.write(File.join(root, "preview.json"), manifest.to_json)
      args = %w[blender --background --factory-startup --disable-autoexec --threads 2 --python-exit-code 1 --python /work/render.py -- preview /work/preview.json]
      image = Studio::NativeBlender::Runtime.image(:render)
      Studio::MediaProcess.run!(Studio::MediaProcess.container(args, root: root, image: image), timeout: 120)
      publish(preview, asset, token, blob.id, File.join(root, "preview.glb"))
    end
  rescue ActiveRecord::RecordNotFound
    # The asset or preview was removed while Blender was running.
  rescue StandardError => error
    Rails.logger.warn("Studio animation preview #{preview_id}: #{error.class}")
    StudioAnimationPreview.where(id: preview_id, attempt_token: token, status: "queued")
      .update_all(status: "failed", updated_at: Time.current)
  end

  private

  def publish(preview, asset, token, revision, path)
    output = nil
    published = false
    File.open(path, "rb") do |file|
      output = ActiveStorage::Blob.build_after_unfurling(io: file, filename: "preview.glb",
        content_type: "model/gltf-binary", identify: false)
      output.save!
      output.upload_without_unfurling(file)
    end
    asset.with_lock do
      return unless asset.native_animation_model? && asset.animation_source.blob.id == revision
      preview.with_lock do
        return unless preview.attempt_token == token && preview.status == "queued"
        preview.file = output
        preview.update!(status: "ready")
      end
    end
    published = true
  ensure
    output.purge_later if output&.persisted? && !published
  end
end
