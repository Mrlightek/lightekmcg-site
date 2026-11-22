# frozen_string_literal: true

module Studio
  module Animation
    class SceneSpec
      MODES = %w[2d 2_5d 3d].freeze
      VISEMES = %w[X A B C D E F G H].freeze
      MAX_DURATION_MS = 30_000

      def self.normalize(value)
        new.normalize(value)
      end

      def normalize(value)
        spec = object(value, %w[aspect_ratio fps duration_ms layers audio_asset_id camera])
        @duration = integer(spec.fetch("duration_ms", 5_000), "duration_ms", 1_000..MAX_DURATION_MS)
        ratio = spec.fetch("aspect_ratio", "9:16")
        fps = spec.fetch("fps", 30)
        invalid("aspect_ratio must be 9:16 or 16:9") unless %w[9:16 16:9].include?(ratio)
        invalid("fps must be 24 or 30") unless fps.is_a?(Integer) && [24, 30].include?(fps)
        {
          "aspect_ratio" => ratio, "fps" => fps, "duration_ms" => @duration,
          "camera" => camera(spec.fetch("camera", {})),
          "layers" => array(spec.fetch("layers", []), "layers", 24).map { |item| layer(item) }
        }.tap do |result|
          result["audio_asset_id"] = asset_id(spec["audio_asset_id"]) if spec["audio_asset_id"]
        end
      end

      private

      def camera(value)
        fields = %w[position rotation lens keyframes]
        data = object(value, fields)
        {
          "position" => vector(data.fetch("position", [0, -8, 0])),
          "rotation" => vector(data.fetch("rotation", [90, 0, 0])),
          "lens" => number(data.fetch("lens", 35), "lens", 12..100),
          "keyframes" => keyframes(data.fetch("keyframes", []), %w[position rotation lens])
        }
      end

      def layer(value)
        data = object(value, %w[asset_id dimension_mode position rotation scale z_layer z_depth relief keyframes action pose_frame mouth])
        mode = data["dimension_mode"]
        invalid("layer dimension_mode is invalid") unless MODES.include?(mode)
        result = {
          "asset_id" => asset_id(data["asset_id"]), "dimension_mode" => mode,
          **transforms({ "position" => [0, 0, 0], "rotation" => [0, 0, 0], "scale" => [1, 1, 1] }.merge(data.slice("position", "rotation", "scale"))),
          "z_layer" => integer(data.fetch("z_layer", 0), "z_layer", -100..100),
          "keyframes" => keyframes(data.fetch("keyframes", []), %w[position rotation scale])
        }
        if mode == "2_5d"
          result["z_depth"] = number(data.fetch("z_depth", 0), "z_depth", -5..20)
          result["relief"] = number(data.fetch("relief", 0), "relief", 0..1)
        elsif data.key?("z_depth") || data.key?("relief")
          invalid("z_depth and relief require a 2_5d layer")
        end
        if mode == "3d"
          if data.key?("action")
            invalid("action must be a name of up to 120 characters") unless data["action"].is_a?(String) && data["action"].length.between?(1, 120)
            result["action"] = data["action"]
          end
          result["pose_frame"] = integer(data["pose_frame"], "pose_frame", 0..100_000) if data.key?("pose_frame")
          invalid("mouth artwork requires a 2d or 2_5d layer") if data.key?("mouth")
        elsif data.key?("action") || data.key?("pose_frame")
          invalid("action and pose_frame require a 3d layer")
        elsif data.key?("mouth")
          result["mouth"] = mouth(data["mouth"])
        end
        result
      end

      def mouth(value)
        data = object(value, %w[position scale variants cues])
        variants = object(data["variants"], VISEMES + ["rest"])
        invalid("Use either X or rest for the rest image") if variants.key?("X") && variants.key?("rest")
        normalized = variants.transform_keys { |key| viseme(key) }.transform_values { |id| asset_id(id) }
        invalid("mouth variants require an X or rest image") unless normalized.key?("X")
        previous_end = 0
        cues = array(data.fetch("cues", []), "mouth cues", 600).map do |item|
          cue = object(item, %w[start_ms end_ms viseme])
          start = integer(cue["start_ms"], "cue start_ms", 0...@duration)
          finish = integer(cue["end_ms"], "cue end_ms", (start + 1)..@duration)
          invalid("lip-sync cues must be ordered and non-overlapping") if start < previous_end
          previous_end = finish
          { "start_ms" => start, "end_ms" => finish, "viseme" => viseme(cue["viseme"]) }
        end
        { "position" => vector(data.fetch("position", [0, 0, 0])),
          "scale" => vector(data.fetch("scale", [0.3, 0.3, 0.3]), scale: true),
          "variants" => normalized, "cues" => cues }
      end

      def viseme(value)
        value = "X" if value == "rest"
        invalid("unknown viseme") unless VISEMES.include?(value)
        value
      end

      def keyframes(value, fields)
        previous = -1
        array(value, "keyframes", 120).map do |item|
          key = object(item, fields + ["time_ms"])
          time = integer(key["time_ms"], "keyframe time_ms", 0...@duration)
          invalid("keyframes need strictly increasing timestamps") if time <= previous
          invalid("keyframe needs at least one animated value") if key.length < 2
          previous = time
          transforms(key.except("time_ms")).merge("time_ms" => time)
        end
      end

      def transforms(data)
        data.to_h do |field, value|
          [field, field == "lens" ? number(value, field, 12..100) : vector(value, scale: field == "scale")]
        end
      end

      def vector(value, scale: false)
        invalid("transforms must be arrays of three numbers") unless value.is_a?(Array) && value.size == 3
        value.map { |component| number(component, "transform", scale ? 0.001..100 : -3600..3600) }
      end

      def object(value, keys)
        invalid("expected an object containing only #{keys.join(', ')}") unless value.is_a?(Hash) && (value.keys - keys).empty?
        value
      end

      def array(value, label, max)
        invalid("#{label} must be an array of up to #{max} items") unless value.is_a?(Array) && value.size <= max
        value
      end

      def asset_id(value) = integer(value, "asset ID", 1..(2**63 - 1))

      def integer(value, label, range)
        invalid("#{label} is out of range") unless value.is_a?(Integer) && range.cover?(value)
        value
      end

      def number(value, label, range)
        invalid("#{label} is out of range") unless value.is_a?(Numeric) && value.finite? && range.cover?(value)
        value
      end

      def invalid(message) = raise(ArgumentError, message)
    end
  end
end
