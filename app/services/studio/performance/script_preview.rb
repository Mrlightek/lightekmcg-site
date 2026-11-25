# frozen_string_literal: true

module Studio
  module Performance
    module ScriptPreview
      DURATION = 20
      FPS = 12
      EXAMPLE = <<~FOUNTAIN.freeze
        EXT. PARK BENCH - NIGHT

        [[SHOT: WIDE @ 0]]
        Alex walks to the bench.

        [[SHOT: MEDIUM @ 4]]
        Alex turns and sits.

        [[SHOT: CLOSE @ 7]]
        ALEX
        We can build this world together.

        [[SHOT: WIDE @ 16.75]]
        Alex stands.
      FOUNTAIN
      CAMERAS = {
        "wide" => { "location" => [-1.1, -5, 1.50], "look_at" => [-0.25, 0, 1.18], "ortho_scale" => 4.8 },
        "medium" => { "location" => [1.0, -4, 1.50], "look_at" => [0, 0.1, 1.22], "ortho_scale" => 3.55 },
        "close" => { "location" => [0.1, -4, 1.80], "look_at" => [0, 0.2, 1.70], "ortho_scale" => 1.75 }
      }.freeze
      HEADING = /\A(?:INT\.|EXT\.|INT\.?\/EXT\.|I\/E\.)\s+\S/i
      SHOT = /\A\[\[SHOT:\s*(WIDE|MEDIUM|CLOSE)\s*@\s*(\d{1,2}(?:\.\d{1,2})?)\s*\]\]\z/i

      def self.parse(value)
        raise ArgumentError, "Use a short Fountain script up to 4,000 bytes" unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= 4000 && !value.include?("\0")
        script = value.gsub(/\r\n?/, "\n").strip
        lines = script.lines.map(&:strip)
        heading = lines.shift
        unless heading && HEADING.match?(heading) && heading.length <= 120 && lines.none? { |line| HEADING.match?(line) }
          raise ArgumentError, "Start with one Fountain scene heading, such as EXT. PARK BENCH - NIGHT"
        end

        cuts = []
        dialogue = nil
        speaker = nil
        dialogue_index = nil
        lines.each_with_index do |line, index|
          next if index == dialogue_index

          if line.start_with?("[[")
            match = SHOT.match(line)
            raise ArgumentError, "Use shot notes like [[SHOT: MEDIUM @ 4]] with seconds from 0 to 19.99" unless match
            time = Float(match[2])
            frame = (time * FPS).round + 1
            unless time < DURATION && frame <= DURATION * FPS && (cuts.empty? ? time.zero? : frame > cuts.last.fetch("frame"))
              raise ArgumentError, "Start at second 0 and put each shot on a later frame within 20 seconds"
            end
            cuts << { "camera" => match[1].downcase, "frame" => frame, "seconds" => time }
          elsif line.match?(/\A@?[[:upper:]][[:upper:]\d .'-]{0,59}\z/) && lines[index + 1].to_s.match?(/\A(?!\[\[)\S/)
            raise ArgumentError, "Use one speaker and one short line of dialogue for the bench preview" if speaker
            speaker = line.delete_prefix("@")
            dialogue_index = index + 1
            dialogue = lines[dialogue_index]
            continuation = lines[dialogue_index + 1]
            if continuation && !continuation.empty? && !SHOT.match?(continuation)
              raise ArgumentError, "Put the dialogue on one line, followed by a blank line before the next action"
            end
          end
        end

        raise ArgumentError, "Use 1–16 camera cues beginning at second 0" unless cuts.length.between?(1, 16)
        unless dialogue && dialogue.length <= 80
          raise ArgumentError, "Add an uppercase speaker cue followed by one spoken line of up to 80 characters"
        end

        { "script" => script, "heading" => heading, "speaker" => speaker, "dialogue" => dialogue, "cuts" => cuts }
      end

      def self.stage(staging, plan)
        cuts = plan.fetch("cuts")
        cameras = cuts.map { |cut| cut.fetch("camera") }.uniq.map do |camera|
          { "id" => camera, "name" => camera.capitalize, "type" => "camera",
            "definition" => CAMERAS.fetch(camera).merge("camera_type" => "ORTHO", "sensor_fit" => "HORIZONTAL") }
        end
        staging.merge(
          "script_frame_end" => DURATION * FPS,
          "objects" => staging.fetch("objects") + cameras,
          "settings" => staging.fetch("settings").merge(
            "fps" => FPS, "camera_cuts" => cuts.map { |cut| { "camera_id" => cut.fetch("camera"), "frame" => cut.fetch("frame") } }
          )
        )
      end
    end
  end
end
