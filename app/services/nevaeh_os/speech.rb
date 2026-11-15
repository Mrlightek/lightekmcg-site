# frozen_string_literal: true
require 'digest'
require 'json'
module NevaehOs
  module Speech
    module_function
    SPOKEN_LIMIT=600
    QUEUE_TIMEOUT=2.minutes
    def normalize(text)
      raise ArgumentError,'Use a response of 1–20,000 characters' unless text.is_a?(String) && text.length.between?(1,20000) && !text.include?("\0")
      clean=text.gsub(/```.*?```/m,' ').gsub(/\[([^\]]+)\]\([^)]+\)/,'\\1').gsub(%r{https?://\S+},' ').gsub(/^[\s#>*-]+/,'').delete('`*').gsub(/\s+/,' ').strip
      raise ArgumentError,'There is no spoken text in this response' if clean.empty?
      truncated=clean.length>SPOKEN_LIMIT
      if truncated
        sample=clean.first(SPOKEN_LIMIT)
        boundary=sample.rindex(/[.!?]\s/) || sample.rindex(/\s/) || SPOKEN_LIMIT-1
        clean=sample.first(boundary+1).strip
      end
      [clean,truncated]
    end
    def request!(actor:,text:,request_key:,voice:'nevaeh-natural',speed:170)
      spoken,truncated=normalize(text)
      fingerprint=Digest::SHA256.hexdigest([spoken,truncated,voice,speed].to_json)
      actor.with_lock do
        if (existing=NevaehSpeech.find_by(user:actor,request_key:request_key))
          raise ArgumentError,'This speech request belongs to different text or voice settings' unless existing.fingerprint==fingerprint
          raise ArgumentError,'This speech clip expired. Read the response again with a new request.' if existing.expires_at<=Time.current
          return existing
        end
        raise ArgumentError,'Wait for your current speech clips or stop them before preparing another' if NevaehSpeech.where(user:actor,status:%w[queued running]).count>=3
        speech=NevaehSpeech.create!(user:actor,request_key:request_key,fingerprint:fingerprint,text:spoken,truncated:truncated,voice:voice,speed:speed,expires_at:1.day.from_now)
        SpeechPlaylist.parts(spoken).each_with_index { |part,index| speech.segments.create!(position:index,text:part) }
        SpeechJob.perform_later(speech.id)
        speech
      end
    end
    def owned!(actor,id)
      speech=NevaehSpeech.where(user:actor).where('expires_at > ?',Time.current).find(id)
      expire_stalled!(speech)
      speech
    end
    def expire_stalled!(speech)
      speech.with_lock do
        if speech.status=='queued' && speech.created_at<QUEUE_TIMEOUT.ago
          speech.update!(status:'failed',error:'The voice worker did not start within two minutes. It may be busy or offline. Read the reply again after the worker is available.')
        elsif speech.status=='running' && speech.started_at && speech.started_at<10.minutes.ago
          speech.update!(status:'failed',error:'Speech preparation was interrupted. Read the response again to create a new request.')
        end
      end
    end
    def receipt(speech)
      since=speech.status=='running' ? speech.started_at : speech.created_at
      playlist=SpeechPlaylist.timeline(speech)
      {id:speech.id,status:speech.status,elapsed_seconds:[(Time.current-(since || Time.current)).to_i,0].max,duration:speech.duration,text:speech.text,truncated:speech.truncated,voice:speech.voice,error:speech.error,
        playlist_url:"/dashboard/nevaeh/speech/#{speech.id}/playlist.m3u8",playlist_ready:playlist[:items].any?,playlist_items:playlist[:items],playlist_duration:playlist[:duration],playlist_frames:playlist[:mouth_frames],playlist_total:speech.segments.count,
        engine:speech.voice.start_with?('nevaeh-') ? 'kokoro_onnx' : 'espeak_ng',mouth_mode:'volume',mouth_frames:speech.status=='ready' ? speech.mouth_frames : [],audio_url:speech.status=='ready' && speech.audio.attached? ? "/dashboard/nevaeh/speech/#{speech.id}/audio" : nil}
    end
    def cancel!(actor,id)
      speech=owned!(actor,id)
      speech.with_lock { speech.update!(status:'cancelled',error:nil) if %w[queued running].include?(speech.status) }
      speech
    end
    def chunks(text)
      rest=text.dup;out=[]
      until rest.empty?
        ending=rest.length<=900 ? rest.length : (rest.first(900).rindex(/\s/)&.+(1) || 900)
        out<<rest.slice!(0,ending)
      end
      out
    end
    def command_in_runtime(command,root)
      Rails.env.production? ? Studio::MediaProcess.container(command.map { |part| part.gsub(root,'/work') },root:root,image:Studio::NativeBlender::Runtime.image(:media)) : command
    end
    def generate!(speech)
      expire_stalled!(speech)
      claimed=false
      speech.with_lock do
        return unless speech.status=='queued'
        SpeechPlaylist.parts(speech.text).each_with_index { |part,index| speech.segments.create!(position:index,text:part) } unless speech.segments.exists?
        speech.update!(status:'running',started_at:Time.current,error:nil);claimed=true
      end
      speech.user.reload
      cancel=-> { speech.reload.status!='running' || speech.expires_at<=Time.current }
      Studio::MediaProcess.temporary_directory('nevaeh-speech-') do |root|
        paths=speech.segments.map do |segment|
          return if cancel.call
          SpeechPlaylist.render!(speech,segment,root,cancel)
        end
        return if cancel.call
        # Generated, fixed local filenames only; the concat manifest never contains user paths.
        File.write(File.join(root,'parts.txt'),paths.each_index.map { |index| "file 'part-#{index}.wav'" }.join("\n"))
        destination=File.join(root,'speech.wav')
        command=['ffmpeg','-v','error','-y','-f','concat','-safe','1','-i',File.join(root,'parts.txt'),'-ac','1','-ar','16000',destination]
        Studio::MediaProcess.run!(command_in_runtime(command,root),timeout:45,cancel_if:cancel)
        probe=['ffprobe','-v','error','-show_entries','format=duration','-of','json',destination]
        duration=Float(JSON.parse(Studio::MediaProcess.run!(command_in_runtime(probe,root),timeout:15)).fetch('format').fetch('duration'))
        raise ArgumentError,'Speech exceeds the two-minute clip limit; read a shorter section' unless duration.finite? && duration.between?(0.05,120)
        File.open(destination,'rb') do |file|
          speech.with_lock do
            return if speech.status!='running'
            speech.audio.attach(io:file,filename:"nevaeh-#{speech.id}.wav",content_type:'audio/wav',identify:false)
          end
        end
        frames=Studio::Performance::AudioEnvelope.call(speech,first:0,duration:duration)
        raise ArgumentError,'Speech timing is invalid' unless frames.size.between?(1,3100) && frames.all? { |row| row['time'].is_a?(Numeric) && row['time'].finite? && row['value'].is_a?(Numeric) && row['value'].finite? && row['value'].between?(0,1) }
        speech.with_lock do
          speech.update!(status:'ready',duration:duration,mouth_frames:frames) if speech.status=='running' && speech.expires_at>Time.current
        end
      end
    rescue StandardError=>error
      if claimed
        speech.with_lock { speech.update!(status:'failed',error:error.message.to_s.first(1000)) if speech.status=='running' }
      end
      raise
    end
    def sweep!
      NevaehSpeech.where(status:'queued').where('created_at < ?',QUEUE_TIMEOUT.ago).update_all(status:'failed',error:'The voice worker did not start within two minutes. It may be busy or offline. Read the reply again after the worker is available.')
      NevaehSpeech.where(status:'running').where('started_at < ?',10.minutes.ago).update_all(status:'failed',error:'Speech preparation was interrupted. Read the response again to create a new request.')
      NevaehSpeech.where('expires_at <= ?',Time.current).order(:id).limit(100).each(&:destroy!)
    end
  end
end
