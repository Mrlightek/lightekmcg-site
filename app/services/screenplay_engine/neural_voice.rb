# frozen_string_literal: true
module ScreenplayEngine
  module NeuralVoice
    VOICES = %w[nevaeh-natural nevaeh-warm].freeze
    module_function
    def synthesize!(text:, path:, voice:, speed:, cancel_if: nil)
      script=Rails.root.join('docker/studio-media/voice/synthesize.py').to_s
      command=if Rails.env.production?
        Studio::MediaProcess.container(['/opt/lightek-voice/venv/bin/python','/opt/lightek-voice/synthesize.py','--output',"/work/#{File.basename(path)}",'--voice',voice,'--speed',speed.to_s],root:File.dirname(path),image:Studio::NativeBlender::Runtime.image(:media),stdin:true)
      else
        [ENV.fetch('LIGHTEK_VOICE_PYTHON','python3'),script,'--output',path,'--voice',voice,'--speed',speed.to_s]
      end
      Studio::MediaProcess.run!(command,timeout:180,stdin_data:text,cancel_if:cancel_if)
      raise 'Natural voice produced no audio. Rebuild the Studio media runtime.' unless File.size?(path)
      path
    rescue Errno::ENOENT
      raise ArgumentError,'Install the natural voice runtime or rebuild the Studio media image'
    rescue Timeout::Error
      raise ArgumentError,'Natural voice took too long. Try a shorter response or choose a basic voice in Voice options.'
    rescue RuntimeError
      raise ArgumentError,'Natural voice is unavailable. Check the Studio voice worker or choose a basic voice in Voice options.'
    end
  end
end
