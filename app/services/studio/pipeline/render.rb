# frozen_string_literal: true

module Studio
  module Pipeline
    class Render
      CAPABILITY = "studio.pipeline.render"
      LIGHTING = %w[studio_soft dramatic_rim outdoor_day].freeze
      MAX_FRAMES = 900
      MAX_ASSETS = 12

      def self.glb_clips(path)
        File.open(path, "rb") do |io|
          magic, version, size, chunk, type = io.read(20).unpack("a4VVVa4")
          raise ArgumentError, "Invalid GLB" unless magic == "glTF" && version == 2 && size == io.size &&
            type == "JSON" && chunk.between?(4, [size - 20, 32.megabytes].min)
          Array(JSON.parse(io.read(chunk))["animations"]).map.with_index do |animation, index|
            animation["name"].presence || "Anim_#{index}"
          end
        end
      end

      def initialize(access, payload)
        @access = access
        @payload = payload
      end

      def submit
        render_key = @payload["requestKey"].to_s
        raise ArgumentError, "Invalid render request key" unless render_key.match?(/\A[0-9a-f-]{36}\z/i)
        assets = @payload.fetch("objects")
        raise ArgumentError, "Add one to #{MAX_ASSETS} assets" unless assets.is_a?(Array) && assets.size.between?(1, MAX_ASSETS)
        engine = @payload.fetch("renderEngine")
        lighting = @payload.fetch("lightingPreset")
        raise ArgumentError, "Invalid engine or lighting preset" unless %w[EEVEE CYCLES].include?(engine) && LIGHTING.include?(lighting)
        width, height = @payload.fetch("resolution")
        raise ArgumentError, "Use even dimensions up to 1920 by 1080" unless
          width.is_a?(Integer) && height.is_a?(Integer) && width.even? && height.even? &&
          width.between?(64, 1920) && height.between?(64, 1080)
        fps = @payload.fetch("fps")
        seconds = number(@payload.fetch("durationSeconds"), 0.1, 30)
        raise ArgumentError, "Use an integer FPS between 1 and 30, with at most #{MAX_FRAMES} frames" unless
          fps.is_a?(Integer) && fps.between?(1, 30) && (seconds * fps).round.between?(1, MAX_FRAMES)
        camera = @payload.fetch("camera")
        position = vector(camera.fetch("position"))
        target = vector(camera.fetch("target"))
        raise ArgumentError, "Camera target must differ from camera position" if position == target

        operation = nil
        created = false
        @access.user.with_lock do
          operation = @access.renders.where("studio_operations.metadata ->> 'pipeline_request' = ?", render_key).first
          next if operation
          assets_by_id = @access.assets.where(id: assets.map { |row| Integer(row.fetch("assetId")) }, status: "ready")
            .with_attached_proxy.index_by(&:id)
          blobs = {}
          rows = assets.map.with_index do |row, index|
            asset = assets_by_id[Integer(row.fetch("assetId"))]
            raise ArgumentError, "Asset is unavailable or is not scene-ready" unless asset&.proxy&.attached? && asset.kind.in?(%w[glb blend])
            clip = row["animationClip"]
            clips = self.class.clips(asset)
            raise ArgumentError, "Animation clip is unavailable for #{asset.name}" unless clip.nil? || (clip.is_a?(String) && clips.include?(clip))
            loop_animation = row.fetch("loopAnimation", true)
            raise ArgumentError, "loopAnimation must be true or false" unless [true, false].include?(loop_animation)
            scale = vector(row.fetch("scale"), min: 0.01, max: 100)
            blobs[asset.id] = asset.proxy.blob
            {"id" => "object-#{index + 1}", "glbPath" => "asset-#{asset.id}.glb", "position" => vector(row.fetch("position")),
              "rotationEulerDeg" => vector(row.fetch("rotationEulerDeg")), "scale" => scale,
              "animationClip" => clip, "loopAnimation" => loop_animation}
          end
          raise ArgumentError, "Render sources exceed 250 MB" if blobs.values.uniq.sum(&:byte_size) > 250.megabytes
          project = StudioProject.find_or_create_by!(owner: @access.user, site: @access.site, name: "Pipeline Hub")
          operation = project.studio_operations.create!(status: "pending", operation_type: "render", provider: "blender",
            capability: CAPABILITY, intent: {"user_id" => @access.user.id}, cost_quote: {},
            metadata: {"pipeline_request" => render_key, "asset_blobs" => blobs.transform_values(&:id)},
            manifest: {"sceneId" => "pipeline-#{render_key}", "renderEngine" => engine, "lightingPreset" => lighting,
              "resolution" => [width, height], "fps" => fps, "durationSeconds" => seconds,
              "camera" => {"position" => position, "target" => target, "fov" => number(camera.fetch("fov"), 10, 120)},
              "objects" => rows})
          operation.layer_sources.attach(blobs.values.uniq)
          created = true
        end
        if created && !StudioPipelineRenderJob.perform_later(operation.id)
          operation.update!(status: "failed", error_message: "Could not queue the render. Submit again.")
        end
        operation
      end

      def self.clips(asset)
        Array(asset.metadata["pipeline_clips"])
      end

      private

      def number(value, min, max)
        raise ArgumentError, "Number outside allowed range" unless value.is_a?(Numeric) && value.finite? && value.between?(min, max)
        value.to_f
      end

      def vector(value, min: -10_000, max: 10_000)
        raise ArgumentError, "Expected three coordinates" unless value.is_a?(Array) && value.size == 3
        value.map { |component| number(component, min, max) }
      end
    end
  end
end
