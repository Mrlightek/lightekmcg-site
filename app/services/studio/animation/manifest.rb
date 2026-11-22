# frozen_string_literal: true

module Studio
  module Animation
    class Manifest
      def initialize(assets)
        @assets = assets
        @blobs = {}
      end

      def build(spec)
        raise ArgumentError, "Add at least one layer before rendering" if spec.fetch("layers").empty?
        width, height = spec.fetch("aspect_ratio") == "9:16" ? [720, 1280] : [1280, 720]
        fps = spec.fetch("fps")
        duration = spec.fetch("duration_ms")
        layers = spec.fetch("layers").map do |layer|
          asset = find_asset(layer.fetch("asset_id"))
          mode = asset.dimension_mode || "3d"
          unless (asset.animation_role.nil? || %w[character prop background].include?(asset.animation_role)) &&
              (mode == layer["dimension_mode"] || (mode == "2d" && layer["dimension_mode"] == "2_5d"))
            raise ArgumentError, "Asset #{asset.id} does not match the requested layer type"
          end
          layer.except("mouth").merge("source" => register(asset.animation_source)).tap do |entry|
            entry["starter"] = true unless asset.animation_role?
            if (mouth = layer["mouth"])
              entry["mouth"] = mouth.merge("variants" => mouth.fetch("variants").transform_values { |id| role_source(id, "viseme") })
            end
          end
        end
        audio = role_source(spec["audio_asset_id"], "audio") if spec["audio_asset_id"]
        total_size = @blobs.values.sum(&:byte_size)
        raise ArgumentError, "Render inputs exceed 256 MB" if total_size > 256.megabytes
        manifest = spec.except("audio_asset_id", "layers").merge(
          "version" => 1, "width" => width, "height" => height,
          "frame_count" => (duration * fps + 999) / 1000, "layers" => layers, "audio" => audio
        )
        [manifest, @blobs]
      end

      private

      def find_asset(id)
        @assets.find(id)
      rescue ActiveRecord::RecordNotFound
        raise ArgumentError, "Asset #{id} is unavailable in your library"
      end

      def role_source(id, role)
        asset = find_asset(id)
        raise ArgumentError, "Asset #{id} must be a #{role} asset" unless asset.animation_role == role
        register(asset.file)
      end

      def register(attachment)
        raise ArgumentError, "One of the scene’s assets has no renderable file" unless attachment.attached?
        blob = attachment.blob
        extension = blob.filename.extension.to_s.downcase
        formats = StudioAsset::ANIMATION_IMAGE_EXTENSIONS + StudioAsset::ANIMATION_MODEL_EXTENSIONS + StudioAsset::ANIMATION_AUDIO_EXTENSIONS
        raise ArgumentError, "Unsupported render input format" unless formats.include?(extension)
        path = "inputs/#{blob.id}.#{extension}"
        @blobs[path] = blob
        path
      end
    end
  end
end
