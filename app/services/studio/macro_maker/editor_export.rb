module Studio
  module MacroMaker
    module EditorExport
      SURFACES = {"photocraft" => "image", "effectcraft" => "motion"}.freeze

      def self.extension(upload, engine, asset_paths: [], assets: [])
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.positive? && upload.size <= Runner::MAX_UPLOAD
          raise ArgumentError, "Upload an editor export up to 20 MiB"
        end

        file = upload.tempfile
        if engine == "effectcraft"
          EffectCraftExport.load(file.read).validate_assets!(asset_paths, assets)
          return ".ecproj"
        end

        if File.extname(upload.original_filename).downcase == ".pcraft" && file.read(4) == "PK\x03\x04".b
          return ".pcraft"
        end

        file.rewind
        Runner::IMAGE_EXTENSIONS.fetch(Marcel::MimeType.for(file)) { raise ArgumentError, "Export a PhotoCraft project or image" }
      ensure
        file&.rewind
      end
    end
  end
end
