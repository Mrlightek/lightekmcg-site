# frozen_string_literal: true
module Studio
  module Editors
    class Export
      def self.start!(scene:, actor:, kind:, request_key:, image: nil)
        key = request_key.to_s
        raise ArgumentError, "Invalid export request" unless key.match?(/\A[a-zA-Z0-9_-]{16,100}\z/)
        operation = nil
        enqueue = false
        scene.with_lock do
          document = Document.new(scene: scene, actor: actor, kind: kind)
          source = document.normalize(document.load || {})
          operation = scene.studio_operations.where(capability: "studio.editor.export").find_by("metadata ->> 'request_key' = ?", key) if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
          operation ||= scene.studio_operations.where(capability: "studio.editor.export").detect { |item| item.metadata["request_key"] == key }
          if operation
            enqueue = operation.status == "pending"
            next
          end
          operation = scene.studio_operations.create!(studio_project: scene.studio_project, operation_type: "edit_media", provider: kind == "photo" ? "minipaint" : "moviemasher", capability: "studio.editor.export", status: "pending", intent: {"user_id" => actor.id}, manifest: {"editor_kind" => kind, "document" => source}, metadata: {"request_key" => key})
          if kind == "photo"
            raise ArgumentError, "Export the current image from Photo Studio" unless image.respond_to?(:tempfile)
            uploaded = Studio::Assets::Upload.call(file: image, user: actor, site: scene.studio_project.site, purpose: "studio_asset")
            blob = ActiveStorage::Blob.find_signed!(uploaded.fetch(:signed_id))
            raise ArgumentError, "Export must be a PNG image" unless blob.content_type == "image/png"
            operation.performance_sources.attach(blob)
          else
            access = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => scene.studio_project.site_id)
            ids = source.fetch("definitions").map { |definition| definition.fetch("id").split(".").last.to_i }
            assets = StudioAsset.for_actor(access).where(site_id: scene.studio_project.site_id, id: ids).includes(file_attachment: :blob).to_a
            raise ArgumentError, "Use at most 1 GB of source media per export" if assets.sum { |asset| asset.file.blob.byte_size } > 1.gigabyte
            sources = assets.map do |asset|
              operation.performance_sources.attach(asset.file.blob)
              {"id" => asset.id, "blob_id" => asset.file.blob.id}
            end
            raise ArgumentError, "Add at least one clip before exporting" if source.fetch("mash").fetch("tracks", []).all? { |track| Array(track["clips"]).empty? }
            operation.update!(manifest: operation.manifest.merge("sources" => sources))
          end
          enqueue = true
        end
        StudioEditorExportJob.perform_later(operation.id) if enqueue
        operation
      end
    end
  end
end
