# frozen_string_literal: true
module Studio
  module Editing
    class Timeline
      def self.normalize(raw, assets:, allow_empty: false)
        data=raw.to_h.deep_stringify_keys
        output=data.fetch("output","video")
        raise ArgumentError,"Choose video or audio output" unless %w[video audio].include?(output)
        width=Integer(data.fetch("width",1280));height=Integer(data.fetch("height",720))
        raise ArgumentError,"Use even dimensions from 64 to 4096" unless [width,height].all?{|n|n.between?(64,4096)&&n.even?}
        fps=Integer(data.fetch("fps",24))
        raise ArgumentError,"Choose 24, 25, 30, 48, 50 or 60 fps" unless [24,25,30,48,50,60].include?(fps)
        preset=data.fetch("export_preset","review")
        raise ArgumentError,"Unknown delivery preset" unless %w[review master].include?(preset)
        tracks=Array(data.fetch("tracks",[])).map do |track|
          track=track.to_h.deep_stringify_keys
          {"id"=>Integer(track.fetch("id")).clamp(0,15),"name"=>track.fetch("name", "Track").to_s.first(60),"gain"=>number(track.fetch("gain",1),0,4),"pan"=>number(track.fetch("pan",0),-1,1),"muted"=>ActiveModel::Type::Boolean.new.cast(track["muted"]),"solo"=>ActiveModel::Type::Boolean.new.cast(track["solo"])}
        end
        raise ArgumentError,"Use at most sixteen unique tracks" if tracks.length>16 || tracks.map{|t|t["id"]}.uniq.length!=tracks.length
        clips=Array(data.fetch("clips"))
        raise ArgumentError,"Add between one and sixty-four clips" unless clips.length.between?(allow_empty ? 0 : 1,64)
        normalized=clips.map do |value|
          clip=value.to_h.deep_stringify_keys
          asset=assets.fetch(Integer(clip.fetch("asset_id"))) { raise ArgumentError,"Media asset is unavailable" }
          raise ArgumentError,"Wait for media processing to finish" unless asset.status=="ready" && %w[video image audio].include?(asset.kind)
          first=number(clip.fetch("in",0),0,600);last=number(clip.fetch("out"),0.01,600);start=number(clip.fetch("start",0),0,600)
          raise ArgumentError,"Clip out point must follow its in point" unless last>first
          duration=asset.metadata["duration"].to_f
          raise ArgumentError,"Clip exceeds the source duration" if asset.kind!="image" && duration>0 && last>duration+0.05
          speed=number(clip.fetch("speed",1),0.25,4)
          length=(last-first)/speed
          raise ArgumentError,"Timeline cannot exceed ten minutes" if start+length>600
          frames=Array(clip["keyframes"])
          raise ArgumentError,"Use at most twenty keyframes per clip" if frames.length>20
          frames=frames.map do |frame|
            frame=frame.to_h.deep_stringify_keys
            {"time"=>number(frame.fetch("time"),0,length),"x"=>number(frame.fetch("x",0),-4096,4096),"y"=>number(frame.fetch("y",0),-4096,4096),"gain"=>number(frame.fetch("gain",1),0,4)}
          end.sort_by{|f|f["time"]}
          raise ArgumentError,"Keyframe times must be distinct" if frames.map{|f|f["time"]}.uniq.length!=frames.length
          {"asset_id"=>asset.id,"kind"=>asset.kind,"in"=>first,"out"=>last,"start"=>start,"track"=>Integer(clip.fetch("track",0)).clamp(0,15),
           "speed"=>speed,"fade_in"=>number(clip.fetch("fade_in",0),0,length),"fade_out"=>number(clip.fetch("fade_out",0),0,length),
           "opacity"=>number(clip.fetch("opacity",1),0,1),"scale"=>number(clip.fetch("scale",1),0.1,4),
           "brightness"=>number(clip.fetch("brightness",0),-1,1),"contrast"=>number(clip.fetch("contrast",1),0,2),"saturation"=>number(clip.fetch("saturation",1),0,3),
           "denoise"=>ActiveModel::Type::Boolean.new.cast(clip["denoise"]),"highpass"=>number(clip.fetch("highpass",0),0,1000),
           "gain"=>number(clip.fetch("gain",1),0,4),"x"=>number(clip.fetch("x",0),-4096,4096),"y"=>number(clip.fetch("y",0),-4096,4096),
           "muted"=>ActiveModel::Type::Boolean.new.cast(clip["muted"]),"keyframes"=>frames,"has_audio"=>asset.metadata["has_audio"]==true||asset.kind=="audio"}
        end
        duration=normalized.map{|c|c["start"]+(c["out"]-c["in"])/c["speed"]}.max || 0
        titles=Array(data.fetch("titles",[]))
        raise ArgumentError,"Use at most thirty-two titles" if titles.length>32
        titles=titles.map do |title|
          title=title.to_h.deep_stringify_keys
          text=title.fetch("text").to_s
          raise ArgumentError,"Title must contain 1–500 characters" unless text.length.between?(1,500) && !text.include?("\0")
          first=number(title.fetch("start",0),0,duration);last=number(title.fetch("end",duration),0,duration)
          raise ArgumentError,"Title end must follow start" unless last>first
          {"text"=>text,"start"=>first,"end"=>last,"x"=>number(title.fetch("x",40),-4096,4096),"y"=>number(title.fetch("y",40),-4096,4096),"size"=>number(title.fetch("size",48),8,300)}
        end
        {"output"=>output,"width"=>width,"height"=>height,"fps"=>fps,"export_preset"=>preset,"tracks"=>tracks,"titles"=>titles,
         "clips"=>normalized.sort_by{|c|[c["track"],c["start"]]},"duration"=>duration}
      end
      def self.number(value,min,max)
        n=Float(value);raise ArgumentError,"Timeline value is outside its range" unless n.finite?&&n.between?(min,max);n
      end
      def self.expression(frames,key,default,start:0)
        return Float(default).to_s if frames.empty?
        result=frames.last.fetch(key).to_f.to_s
        frames.each_cons(2).to_a.reverse_each do |a,b|
          first=a.fetch("time")+start;last=b.fetch("time")+start
          linear="#{a.fetch(key)}+(#{b.fetch(key)}-#{a.fetch(key)})*(t-#{first})/#{last-first}"
          result="if(lt(t,#{last}),#{linear},#{result})"
        end
        "if(lt(t,#{frames.first.fetch('time')+start}),#{frames.first.fetch(key)},#{result})"
      end
      def self.command(timeline, paths:, output:, title_paths: [])
        args=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-filter_complex_threads","1"]
        timeline.fetch("clips").each_with_index do |clip,i|
          args+= ["-loop","1","-framerate",timeline.fetch("fps",24).to_s] if clip["kind"]=="image"
          args += ["-protocol_whitelist","file,pipe","-i",paths.fetch(i)]
        end
        duration=timeline.fetch("duration");filters=[];audio=[];video="base"
        if timeline["output"]=="video"
          filters<<"color=c=black:s=#{timeline['width']}x#{timeline['height']}:r=#{timeline.fetch("fps",24)}:d=#{duration}[base]"
        end
        filters<<"anullsrc=r=48000:cl=stereo,atrim=duration=#{duration}[silence]";audio<<"[silence]"
        timeline["clips"].each_with_index do |clip,i|
          length=(clip["out"]-clip["in"])/clip.fetch("speed",1)
          if timeline["output"]=="video" && clip["kind"]!="audio"
            visual=["trim=start=#{clip['in']}:end=#{clip['out']}","setpts=(PTS-STARTPTS)/#{clip.fetch('speed',1)}", "fps=#{timeline.fetch('fps',24)}",
              "scale=#{(timeline['width']*clip.fetch('scale',1)).round}:#{(timeline['height']*clip.fetch('scale',1)).round}:force_original_aspect_ratio=decrease", "setsar=1",
              "eq=brightness=#{clip.fetch('brightness',0)}:contrast=#{clip.fetch('contrast',1)}:saturation=#{clip.fetch('saturation',1)}", "format=yuva420p", "colorchannelmixer=aa=#{clip.fetch('opacity',1)}"]
            visual<<"fade=t=in:st=0:d=#{clip['fade_in']}:alpha=1" if clip.fetch('fade_in',0)>0
            visual<<"fade=t=out:st=#{length-clip['fade_out']}:d=#{clip['fade_out']}:alpha=1" if clip.fetch('fade_out',0)>0
            visual<<"setpts=PTS+#{clip['start']}/TB"
            filters<<"[#{i}:v]#{visual.join(',')}[v#{i}]"
            x=expression(clip["keyframes"],"x",clip["x"],start:clip["start"]);y=expression(clip["keyframes"],"y",clip["y"],start:clip["start"])
            filters<<"[#{video}][v#{i}]overlay=x='#{x}':y='#{y}':eof_action=pass:enable='between(t,#{clip['start']},#{clip['start']+length})'[layer#{i}]"
            video="layer#{i}"
          end
          track=timeline.fetch("tracks",[]).find{|t|t["id"]==clip["track"]} || {"gain"=>1,"pan"=>0}
          solo=timeline.fetch("tracks",[]).any?{|t|t["solo"]}
          if clip["has_audio"] && !clip["muted"] && !track["muted"] && (!solo || track["solo"])
            gain=expression(clip["keyframes"],"gain",clip["gain"])
            delay=(clip["start"]*1000).round
            sound=["atrim=start=#{clip['in']}:end=#{clip['out']}","asetpts=PTS-STARTPTS", "aformat=sample_rates=48000:channel_layouts=stereo"]
            speed=clip.fetch('speed',1).to_f
            while speed>2
              sound<<"atempo=2";speed/=2
            end
            while speed<0.5
              sound<<"atempo=0.5";speed/=0.5
            end
            sound<<"atempo=#{speed}"
            sound<<"highpass=f=#{clip['highpass']}" if clip.fetch('highpass',0)>0
            sound<<"afftdn=nf=-25" if clip['denoise']
            sound<<"volume='(#{gain})*#{track['gain']}':eval=frame"
            pan=track['pan'].to_f
            sound<<"pan=stereo|c0=#{1-[pan,0].max}*c0|c1=#{1-[-pan,0].max}*c1"
            sound<<"afade=t=in:st=0:d=#{clip['fade_in']}" if clip.fetch('fade_in',0)>0
            sound<<"afade=t=out:st=#{length-clip['fade_out']}:d=#{clip['fade_out']}" if clip.fetch('fade_out',0)>0
            sound<<"adelay=#{delay}|#{delay}"
            filters<<"[#{i}:a]#{sound.join(',')}[a#{i}]"
            audio<<"[a#{i}]"
          end
        end
        if timeline["output"]=="video"
          timeline.fetch("titles",[]).each_with_index do |title,i|
            # Text is staged in generated files, never interpolated into filter syntax.
            path=title_paths.fetch(i)
            raise ArgumentError,"Unsafe title staging path" unless path.match?(%r{\A[/a-zA-Z0-9_.-]+\z})
            filters<<"[#{video}]drawtext=textfile=#{path}:expansion=none:fontcolor=white:fontsize=#{title['size']}:x=#{title['x']}:y=#{title['y']}:box=1:boxcolor=black@0.45:boxborderw=10:enable='between(t,#{title['start']},#{title['end']})'[title#{i}]"
            video="title#{i}"
          end
        end
        filters<<"#{audio.join}amix=inputs=#{audio.length}:duration=longest:normalize=0,alimiter=limit=0.95[aout]"
        args += ["-filter_complex",filters.join(';'),"-map","[aout]"]
        master=timeline.fetch("export_preset","review")=="master"
        if timeline["output"]=="video"
          args += ["-map","[#{video}]"]
          args += master ? ["-c:v","prores_ks","-profile:v","3","-pix_fmt","yuv422p10le","-c:a","pcm_s24le"] : ["-c:v","libx264","-pix_fmt","yuv420p","-preset","veryfast","-crf","18","-c:a","aac","-b:a","320k","-movflags","+faststart"]
          args += ["-threads","2"]
        else
          args += ["-c:a",master ? "pcm_s24le" : "pcm_s16le"]
        end
        args += ["-ar","48000"]
        args+["-t",duration.to_s,output]
      end
    end
  end
end
