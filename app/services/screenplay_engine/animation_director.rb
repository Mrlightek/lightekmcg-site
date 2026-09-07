module ScreenplayEngine
  class AnimationDirector
    # Basic Viseme mapping (mouth shapes for lip sync)
    VISEME_MAP = {
      /[aeiou]/i => "VISEME_OPEN_VOWEL",
      /[bmp]/i   => "VISEME_CLOSED_LIPS",
      /[fv]/i    => "VISEME_DENTAL",
      /[w]/i     => "VISEME_ROUNDED"
    }.freeze

    # Convert dialogue into frame-by-frame mouth shapes
    def self.generate_phonemes(text, start_frame, fps = 24)
      phoneme_frames = []
      words = text.split(" ")
      current_frame = start_frame

      words.each do |word|
        word.chars.each do |char|
          shape = VISEME_MAP.find { |pattern, _| char =~ pattern }&.last || "VISEME_NEUTRAL"
          phoneme_frames << { frame: current_frame, shape: shape }
          current_frame += 2 # Advance 2 frames per letter focus
        end
        current_frame += 4 # Pause between words
      end

      phoneme_frames
    end

    # Calculate camera shake intensity based on dialogue emotion
    def self.calculate_camera_shake(emotion)
      case emotion
      when :frantic, :desperate
        { intensity: 0.8, noise_scale: 0.3 } # High rumble
      when :frustrated
        { intensity: 0.3, noise_scale: 0.1 } # Moderate jitter
      else
        { intensity: 0.0, noise_scale: 0.0 } # Static camera
      end
    end
  end
end


# Example payload snippet when building the exported Hash:
# scene_data[:lines].map.with_index do |line, idx|
#   start_frame = (idx + 1) * 48 # 2 second offset
#   {
#     speaker: line[:speaker],
#     emotion: line[:emotion],
#     text: line[:text],
#     start_frame: start_frame,
#     shake_data: ScreenplayEngine::AnimationDirector.calculate_camera_shake(line[:emotion]),
#     phonemes: ScreenplayEngine::AnimationDirector.generate_phonemes(line[:text], start_frame)
#   }
# end