require 'json'
require 'open3'

module ScreenplayEngine
  class AudioSynthesizer
    AUDIO_DIR = "./output_audio"

    # Uses local 'espeak' or macOS 'say' (or replace with an API call like ElevenLabs/OpenAI)
    def self.generate_dialogue_audio(speaker, text, line_index)
      Dir.mkdir(AUDIO_DIR) unless Dir.exist?(AUDIO_DIR)
      file_path = File.join(AUDIO_DIR, "#{speaker}_line_#{line_index}.wav")

      # Simple local TTS fallback (Mac 'say' or Linux 'espeak')
      if RUBY_PLATFORM =~ /darwin/
        system("say", "-o", file_path, "--data-format=LEI16@24000", text)
      else
        system("espeak", "-w", file_path, text)
      end

      # Return relative path for Blender to load
      File.expand_path(file_path)
    end
  end
end

# Example usage integrating into the manifest exporter:
def build_manifest_with_audio(script_lines)
  script_lines.map.with_index do |line, idx|
    start_frame = (idx + 1) * 48 # 2 second spacing
    audio_path = ScreenplayEngine::AudioSynthesizer.generate_dialogue_audio(
      line[:speaker], 
      line[:text], 
      idx
    )

    {
      speaker: line[:speaker],
      emotion: line[:emotion],
      text: line[:text],
      start_frame: start_frame,
      audio_file: audio_path
    }
  end
end