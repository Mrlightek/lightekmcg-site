require "json"
require "digest"
module Studio
  module Compute
    module Federation
      class Contract
        TYPES = %w[cube sphere cylinder plane camera point_light sun_light area_light].freeze
        SETTINGS = %w[compute_profile render_engine resolution_x resolution_y resolution_percentage samples fps fps_base frame_start frame_end frame_current world_color world_strength transparent_background active_camera_object_id active_camera shot_board shot_board_receipts source_credits].freeze
        FIELDS = %w[location rotation scale color energy power size lens look_at material animation].freeze
        MATERIAL = %w[color metallic roughness transmission].freeze
        def self.validate!(manifest)
          raise ArgumentError, "Remote CPU manifests must be JSON objects under 512 KiB" unless manifest.is_a?(Hash) && JSON.generate(manifest).bytesize <= 512.kilobytes
          raise ArgumentError, "Unsupported remote scene contract" unless manifest["schema_version"] == "1.0" && manifest.keys.difference(%w[schema_version scene project credits outputs]).empty?
          scene = manifest.fetch("scene")
          raise ArgumentError, "Unsupported remote scene fields" unless scene.is_a?(Hash) && scene.keys.difference(%w[id name settings objects]).empty?
          settings = scene.fetch("settings")
          raise ArgumentError, "Remote CPU currently supports procedural scenes; native sources and advanced settings require source transfer" unless settings.is_a?(Hash) && settings.keys.difference(SETTINGS).empty? && CpuProfile.economy?(manifest)
          # Require already-resolved dimensions: a paid snapshot is never silently rewritten.
          resolved = CpuProfile.settings(settings)
          raise ArgumentError, "Resolve the CPU economy profile before submitting" unless resolved == settings
          start = Integer(settings.fetch("frame_start", 1)); finish = Integer(settings.fetch("frame_end", 1))
          raise ArgumentError, "Remote CPU movies support 1–2400 ordered frames" unless start >= 1 && finish >= start && finish <= 2400
          vector!(settings["world_color"], 4) if settings.key?("world_color")
          number!(settings["world_strength"]) if settings.key?("world_strength")
          base = settings.fetch("fps_base", 1)
          number!(base)
          raise ArgumentError, "Remote frame base must be positive" unless base > 0
          fps = Integer(settings.fetch("fps", 24))
          raise ArgumentError, "Remote frame rate must be 1–60" unless fps.between?(1, 60)
          objects = scene.fetch("objects")
          raise ArgumentError, "Remote scenes support up to 128 procedural objects" unless objects.is_a?(Array) && objects.length <= 128
          objects.each do |object|
            raise ArgumentError, "Remote CPU currently accepts procedural objects, cameras and lights" unless object.is_a?(Hash) && TYPES.include?(object["type"]) && object.keys.difference(%w[id name type definition]).empty?
            raise ArgumentError, "Remote object names must be short strings" unless object["name"].is_a?(String) && object["name"].length.between?(1, 160)
            definition = object.fetch("definition")
            raise ArgumentError, "Unsupported remote object controls" unless definition.is_a?(Hash) && definition.keys.difference(FIELDS).empty?
            %w[location rotation scale look_at].each { |key| vector!(definition[key], 3) if definition.key?(key) }
            vector!(definition["color"], 4) if definition.key?("color")
            %w[energy power size lens].each { |key| number!(definition[key]) if definition.key?(key) }
            if (material = definition["material"])
              raise ArgumentError, "Unsupported remote material" unless material.is_a?(Hash) && material.keys.difference(MATERIAL).empty?
              material.each { |key, value| key == "color" ? vector!(value, 4) : number!(value) }
            end
            if (animation = definition["animation"])
              raise ArgumentError, "Unsupported remote animation" unless animation.is_a?(Hash) && animation.keys.difference(%w[frames fps]).empty?
              raise ArgumentError, "Invalid remote animation frame rate" unless Integer(animation.fetch("fps", fps)).between?(1, 60)
              frames = animation.fetch("frames", [])
              raise ArgumentError, "Remote animation supports up to 100 keys per object" unless frames.is_a?(Array) && frames.length <= 100
              frames.each do |frame|
                raise ArgumentError, "Unsupported remote keyframe" unless frame.is_a?(Hash) && frame.keys.difference(%w[frame location rotation]).empty? && Integer(frame.fetch("frame")).between?(start, finish)
                %w[location rotation].each { |key| vector!(frame[key], 3) if frame.key?(key) }
              end
            end
          end
          raise ArgumentError, "Remote CPU currently requires a movie output" unless manifest["outputs"].is_a?(Hash) && manifest["outputs"]["animation"] == true && manifest["outputs"].keys.difference(%w[animation blend preview bundle glb]).empty? && !manifest["outputs"]["bundle"] && !manifest["outputs"]["glb"] && manifest["outputs"].values.all? { |value| value == true || value == false }
          JSON.parse(JSON.generate(manifest))
        rescue TypeError, KeyError => error
          raise ArgumentError, "Invalid remote scene contract: #{error.message}"
        end
        def self.vector!(value, size)
          raise ArgumentError, "Invalid remote vector" unless value.is_a?(Array) && value.length == size
          value.each { |item| number!(item) }
        end
        def self.number!(value)
          raise ArgumentError, "Remote values must be bounded finite numbers" unless value.is_a?(Numeric) && value.finite? && value.abs <= 100_000
        end
        def self.digest(manifest) = Digest::SHA256.hexdigest(JSON.generate(canonical(manifest)))
        def self.canonical(value)
          case value
          when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
          when Array then value.map { |item| canonical(item) }
          else value
          end
        end
      end
    end
  end
end
