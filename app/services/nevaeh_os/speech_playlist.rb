# frozen_string_literal: true
module NevaehOs
  module SpeechPlaylist
    module_function
    def parts(text)
      rest=text.strip;items=[]
      until rest.empty?
        limit=items.empty? ? 60 : 120
        if rest.length<=limit
          items<<rest;break
        end
        sample=rest.first(limit)
        boundary=sample.rindex(/[.!?]\s/) || sample.rindex(/\s/) || limit-1
        items<<rest.slice!(0,boundary+1).strip
        rest=rest.lstrip
      end
      raise ArgumentError,'Speech playlist is too long' if items.size>12
      items
    end
    def timeline(speech)
      offset=0.0;frames=[];items=[]
      speech.segments.where(status:'ready').each do |segment|
        break unless segment.position==items.size
        frames+=segment.mouth_frames.map { |frame| {'time'=>frame['time']+offset,'value'=>frame['value']} }
        items<<{position:segment.position,text:segment.text,duration:segment.duration,audio_url:"/dashboard/nevaeh/speech/#{speech.id}/segments/#{segment.position}.ts"}
        offset+=segment.duration
      end
      {items:items,duration:offset,mouth_frames:frames}
    end
    def manifest(speech)
      items=timeline(speech)[:items]
      # Fixed 20s ceiling keeps TARGETDURATION constant as the EVENT grows.
      rows=['#EXTM3U','#EXT-X-VERSION:3','#EXT-X-TARGETDURATION:20','#EXT-X-MEDIA-SEQUENCE:0','#EXT-X-PLAYLIST-TYPE:EVENT','#EXT-X-START:TIME-OFFSET=0,PRECISE=YES']
      items.each_with_index do |item,index|
        rows<<'#EXT-X-DISCONTINUITY' if index.positive?
        rows<<format('#EXTINF:%.6f,',item[:duration])
        rows<<item[:audio_url]
      end
      rows<<'#EXT-X-ENDLIST' if %w[ready failed cancelled].include?(speech.status)
      rows.join("\n")+"\n"
    end
    def render_neural!(speech,root,cancel)
      segments=speech.segments.to_a
      publish=-> do
        return if cancel.call
        segments.each do |segment|
          next if segment.status=='ready'
          path=File.join(root,"part-#{segment.position}.json")
          next unless File.file?(path)
          raise ArgumentError,'Speech metadata is too large' if File.size(path)>64000
          data=JSON.parse(File.read(path));duration=data.fetch('duration');frames=data.fetch('mouth_frames')
          valid=duration.is_a?(Numeric) && duration.finite? && duration.between?(0.05,20) && frames.is_a?(Array) && frames.size.between?(1,510)
          valid &&= frames.each_with_index.all? { |row,i| row['time'].is_a?(Numeric) && row['time'].finite? && row['time'].between?(0,duration+0.1) && (i.zero? || row['time']>=frames[i-1]['time']) && row['value'].is_a?(Numeric) && row['value'].finite? && row['value'].between?(0,1) }
          raise ArgumentError,'Speech timing is invalid' unless valid
          File.open(File.join(root,"part-#{segment.position}.wav"),'rb') do |audio|
            File.open(File.join(root,"part-#{segment.position}.ts"),'rb') do |stream|
              speech.with_lock do
                return if speech.status!='running'
                segment.audio.attach(io:audio,filename:"part-#{segment.position}.wav",content_type:'audio/wav',identify:false)
                segment.stream.attach(io:stream,filename:"part-#{segment.position}.ts",content_type:'video/mp2t',identify:false)
                segment.update!(status:'ready',duration:duration,mouth_frames:frames)
              end
            end
          end
        end
      end
      ScreenplayEngine::NeuralVoice.synthesize_playlist!(parts:segments.map(&:text),root:root,voice:speech.voice,speed:speech.speed,cancel_if:cancel,on_tick:publish)
      publish.call
      return if cancel.call
      raise ArgumentError,'Natural voice did not finish its playlist' unless segments.all? { |segment| segment.status=='ready' }
      segments.map { |segment| File.join(root,"part-#{segment.position}.wav") }
    end
    def render!(speech,segment,root,cancel)
      segment.update!(status:'running')
      wav=File.join(root,"part-#{segment.position}.wav")
      encoded=File.join(root,"part-#{segment.position}.ts")
      ScreenplayEngine::AudioSynthesizer.synthesize!(text:segment.text,path:wav,voice:speech.voice,speed:speech.speed,cancel_if:cancel)
      return if cancel.call
      command=['ffmpeg','-v','error','-y','-i',wav,'-ac','1','-ar','24000','-c:a','aac','-b:a','64k','-muxdelay','0','-muxpreload','0','-avoid_negative_ts','make_zero','-f','mpegts',encoded]
      Studio::MediaProcess.run!(Speech.command_in_runtime(command,root),timeout:30,cancel_if:cancel)
      probe=['ffprobe','-v','error','-show_entries','format=duration','-of','json',encoded]
      duration=Float(JSON.parse(Studio::MediaProcess.run!(Speech.command_in_runtime(probe,root),timeout:15)).fetch('format').fetch('duration'))
      raise ArgumentError,'Speech playlist item exceeds its 20 second limit. Choose a faster pace or shorter response.' unless duration.finite? && duration.between?(0.05,20)
      File.open(wav,'rb') { |io| segment.audio.attach(io:io,filename:"part-#{segment.position}.wav",content_type:'audio/wav',identify:false) }
      File.open(encoded,'rb') { |io| segment.stream.attach(io:io,filename:"part-#{segment.position}.ts",content_type:'video/mp2t',identify:false) }
      frames=Studio::Performance::AudioEnvelope.call(segment,first:0,duration:duration)
      raise ArgumentError,'Speech playlist timing is invalid' unless frames.any? && frames.all? { |row| row['time'].is_a?(Numeric) && row['time'].finite? && row['value'].is_a?(Numeric) && row['value'].finite? && row['value'].between?(0,1) }
      speech.with_lock do
        return if speech.status!='running'
        segment.update!(status:'ready',duration:duration,mouth_frames:frames)
      end
      wav
    end
  end
end
