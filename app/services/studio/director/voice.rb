# frozen_string_literal: true
module Studio
  module Director
    class Voice
      def self.voice!(value)
        raise ArgumentError, 'Choose the stock en, en-us, en-gb or ar voice' unless %w[en en-us en-gb ar].include?(value)
        value
      end
      def self.speed!(value)
        raise ArgumentError, 'Choose 100–220 words per minute' unless value.is_a?(Integer) && value.between?(100,220)
        value
      end
      def self.asset!(operation, actor, line, index)
        key = "director-voice-#{operation.id}-#{index}"
        asset = StudioAsset.find_by(owner_id: actor.id, request_key: key)
        return asset if asset&.file&.attached?
        Studio::MediaProcess.temporary_directory('director-voice-') do |root|
          path = File.join(root,'voice.wav')
          ScreenplayEngine::AudioSynthesizer.synthesize!(text: line.fetch('text'), path: path, voice: voice!(line.fetch('voice')), speed: speed!(line.fetch('speed')), cancel_if: -> { operation.reload.status == 'cancelled' })
          command = ['ffprobe','-v','error','-show_entries','format=duration','-of','json',path]
          command = Studio::MediaProcess.container(command.map { |part| part.gsub(root,'/work') }, root: root, image: Studio::NativeBlender::Runtime.image(:media)) if Rails.env.production?
          duration = Float(JSON.parse(Studio::MediaProcess.run!(command, timeout: 30)).fetch('format').fetch('duration'))
          raise ArgumentError, 'Split this dialogue into takes of at most thirty seconds' unless duration.finite? && duration.between?(0.1,30)
          actor.with_lock do
            asset = StudioAsset.find_or_initialize_by(owner_id: actor.id, request_key: key)
            return asset if asset.persisted? && asset.file.attached?
            asset.assign_attributes(site_id: operation.studio_project.site_id, studio_project: operation.studio_project, name: "#{line['speaker']} · synthetic dialogue", kind: 'audio', status: 'ready', metadata: {'duration'=>duration, 'has_audio'=>true, 'synthetic_voice'=>true, 'voice'=>line['voice'], 'speaker'=>line['speaker'], 'transcript'=>line['text'], 'director_operation_id'=>operation.id})
            asset.save!
            asset.file.attach(io: StringIO.new(File.binread(path)), filename: "dialogue-#{operation.id}-#{index}.wav", content_type: 'audio/wav', identify: false)
          end
        end
        asset
      end
    end
  end
end
