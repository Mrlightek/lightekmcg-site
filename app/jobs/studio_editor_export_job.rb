# frozen_string_literal: true
class StudioEditorExportJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation = StudioOperation.find(id)
    operation.with_lock do
      return unless operation.status == "pending" && operation.capability == "studio.editor.export"
      operation.update!(status: "running", started_at: Time.current, error_message: nil)
    end
    actor = User.find(operation.intent.fetch("user_id"))
    Studio::Broadcasting::Access.authorize!(actor, operation.studio_project.site)
    Studio::PwaAccess.new("user_id" => actor.id, "site_id" => operation.studio_project.site_id).projects.find(operation.studio_project_id)
    if operation.provider == "minipaint"
      blob = operation.performance_sources.first.blob
      complete!(operation, blob, "image", "#{operation.studio_project.name.parameterize.presence || 'photo'}.png")
    elsif operation.provider == "moviemasher"
      Studio::MediaProcess.temporary_directory("movie-masher-") do |root|
        FileUtils.mkdir_p(File.join(root, "media"))
        document = operation.manifest.fetch("document").deep_dup
        source_map = operation.manifest.fetch("sources").index_by { |source| source.fetch("id").to_s }
        document.fetch("definitions").each do |definition|
          source = source_map.fetch(definition.fetch("id").split(".").last)
          blob = operation.performance_sources.find { |attachment| attachment.blob_id == source.fetch("blob_id") }&.blob
          raise "The export source is unavailable" unless blob
          filename = "asset-#{source.fetch('id')}"
          File.open(File.join(root, "media", filename), "wb") { |file| blob.download { |chunk| file.write(chunk) } }
          %w[url source audioUrl].each { |key| definition[key] = filename }
          definition.delete("icon")
        end
        File.write(File.join(root, "project.json"), document.to_json)
        command = if Rails.env.production?
          Studio::MediaProcess.container(["node", "/opt/lightek-editors/movie-render.cjs", "/work"], root: root, image: Studio::NativeBlender::Runtime.image(:media))
        else
          [ENV.fetch("STUDIO_NODE_BINARY", "node"), Rails.root.join("docker/studio-media/movie-render.cjs").to_s, root]
        end
        Studio::MediaProcess.run!(command, timeout: 900, cancel_if: -> { operation.reload.status == "cancelled" })
        output = File.join(root, "output/video.mp4")
        raise "Movie Masher did not produce an export" unless File.size?(output)
        File.open(output, "rb") do |file|
          blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: "video.mp4", content_type: "video/mp4", identify: false)
          complete!(operation, blob, "video", "#{operation.studio_project.name.parameterize.presence || 'video'}.mp4")
        end
      end
    else
      raise "Unsupported editor"
    end
  rescue StandardError => error
    operation&.update!(status: "failed", completed_at: Time.current, error_message: error.message.to_s.first(2000)) unless operation&.status == "cancelled"
    raise
  end
  private
  def complete!(operation, blob, kind, filename)
    operation.with_lock do
      return if operation.status == "cancelled"
      artifact = operation.artifacts.create!(kind: kind, filename: filename)
      artifact.file.attach(blob)
      asset = StudioAsset.create!(owner_id: operation.intent.fetch("user_id"), site_id: operation.studio_project.site_id, name: filename, kind: kind, status: "uploaded", request_key: "editor-export-#{operation.id}")
      asset.file.attach(blob)
      operation.update!(status: "completed", completed_at: Time.current, metadata: operation.metadata.merge("asset_id" => asset.id))
      StudioAssetIngestJob.perform_later(asset.id)
    end
  end
end
