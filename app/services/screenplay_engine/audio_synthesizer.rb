require 'json'
require 'open3'
require 'fileutils'

module ScreenplayEngine
  class AudioSynthesizer
    AUDIO_DIR = "./output_audio"

    # Local stock speech and CPU neural speech share the same private WAV path.
    def self.synthesize!(text:, path:, voice: 'en-us', speed: 155, cancel_if: nil)
      raise ArgumentError, 'Dialogue must contain 1–1000 characters' unless text.is_a?(String) && text.length.between?(1,1000) && !text.include?("\0")
      raise ArgumentError, 'Choose an installed voice' unless (%w[en en-us en-gb ar en-us+f3 en-gb+f3 ar+f3]+NeuralVoice::VOICES).include?(voice)
      raise ArgumentError, 'Choose a speaking speed of 100–220 words per minute' unless speed.is_a?(Integer) && speed.between?(100,220)
      return NeuralVoice.synthesize!(text:text,path:path,voice:voice,speed:speed,cancel_if:cancel_if) if NeuralVoice::VOICES.include?(voice)
      command = if Rails.env.production?
        Studio::MediaProcess.container(['espeak-ng','--stdin','-v',voice,'-s',speed.to_s,'-w',"/work/#{File.basename(path)}"], root: File.dirname(path), image: Studio::NativeBlender::Runtime.image(:media), stdin: true)
      else
        [ENV.fetch('STUDIO_TTS_BINARY','espeak-ng'),'--stdin','-v',voice,'-s',speed.to_s,'-w',path]
      end
      Studio::MediaProcess.run!(command, timeout: 180, stdin_data: text, cancel_if: cancel_if)
      raise 'Speech engine produced no audio' unless File.size?(path)
      path
    rescue Errno::ENOENT
      raise ArgumentError, 'Install espeak-ng or rebuild the Studio media image to enable synthetic voices'
    end
    def self.generate_dialogue_audio(speaker, text, line_index)
      FileUtils.mkdir_p(AUDIO_DIR)
      name = speaker.to_s.gsub(/[^a-zA-Z0-9_-]/,'_').first(80)
      index = Integer(line_index)
      raise ArgumentError, 'Choose a nonnegative dialogue index' if index.negative?
      path = File.expand_path(File.join(AUDIO_DIR,"#{name}_line_#{index}.wav"))
      synthesize!(text: text, path: path)
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
