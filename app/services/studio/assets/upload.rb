# frozen_string_literal: true
module Studio
  module Assets
    class Upload
      def self.call(file:,user:,site:,purpose:)
        raise ArgumentError, "Choose a media file" unless file.respond_to?(:tempfile)
        raise ArgumentError, "File must be smaller than 250 MB" if file.size > 250.megabytes
        studio_kind = nil
        if purpose=="studio_asset" && %w[.blend .glb .zip].include?(File.extname(file.original_filename).downcase)
          magic=File.binread(file.tempfile.path,12)
          studio_kind = "blend" if magic.start_with?("BLENDER", "\x1f\x8b".b, "\x28\xb5\x2f\xfd".b)
          studio_kind = "blend" if File.extname(file.original_filename).downcase==".zip" && magic.start_with?("PK\x03\x04".b)
          studio_kind = "glb" if magic.start_with?("glTF")
          raise ArgumentError,"File does not match its asset format" unless studio_kind
        end
        type = Marcel::MimeType.for(file.tempfile, name: file.original_filename, declared_type: file.content_type)
        allowed = Post::MEDIA_TYPES
        type = studio_kind=="blend" ? "application/x-blender" : "model/gltf-binary" if studio_kind
        raise ArgumentError, "Unsupported media type" unless studio_kind || allowed.include?(type)
        blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename,
          content_type: type, identify: false,
          metadata: { "lightek_user_id" => user.id, "lightek_site_id" => site.id, "studio_kind" => studio_kind })
        { signed_id: blob.signed_id, filename: blob.filename.to_s, content_type: type }
      end
    end
  end
end
