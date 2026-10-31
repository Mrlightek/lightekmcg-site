# frozen_string_literal: true
module Studio
  module Editing
    class Timeline
      def self.normalize(raw, assets:)
        data=raw.to_h.deep_stringify_keys
        output=data.fetch("output","video")
        raise ArgumentError,"Choose video or audio output" unless %w[video audio].include?(output)
        width=Integer(data.fetch("width",1280));height=Integer(data.fetch("height",720))
        raise ArgumentError,"Use even dimensions from 64 to 1920" unless [width,height].all?{|n|n.between?(64,1920)&&n.even?}
        clips=Array(data.fetch("clips"))
        raise ArgumentError,"Add between one and sixteen clips" unless clips.length.between?(1,16)
        normalized=clips.map do |value|
          clip=value.to_h.deep_stringify_keys
          asset=assets.fetch(Integer(clip.fetch("asset_id"))) { raise ArgumentError,"Media asset is unavailable" }
          raise ArgumentError,"Wait for media processing to finish" unless asset.status=="ready" && %w[video image audio].include?(asset.kind)
          first=number(clip.fetch("in",0),0,600);last=number(clip.fetch("out"),0.01,600);start=number(clip.fetch("start",0),0,600)
          raise ArgumentError,"Clip out point must follow its in point" unless last>first
          duration=asset.metadata["duration"].to_f
          raise ArgumentError,"Clip exceeds the source duration" if asset.kind!="image" && duration>0 && last>duration+0.05
          raise ArgumentError,"Timeline cannot exceed ten minutes" if start+last-first>600
          frames=Array(clip["keyframes"])
          raise ArgumentError,"Use at most twenty keyframes per clip" if frames.length>20
          frames=frames.map do |frame|
            frame=frame.to_h.deep_stringify_keys
            {"time"=>number(frame.fetch("time"),0,last-first),"x"=>number(frame.fetch("x",0),-1920,1920),"y"=>number(frame.fetch("y",0),-1920,1920),"gain"=>number(frame.fetch("gain",1),0,4)}
          end.sort_by{|f|f["time"]}
          raise ArgumentError,"Keyframe times must be distinct" if frames.map{|f|f["time"]}.uniq.length!=frames.length
          {"asset_id"=>asset.id,"kind"=>asset.kind,"in"=>first,"out"=>last,"start"=>start,"track"=>Integer(clip.fetch("track",0)).clamp(0,15),
           "gain"=>number(clip.fetch("gain",1),0,4),"x"=>number(clip.fetch("x",0),-1920,1920),"y"=>number(clip.fetch("y",0),-1920,1920),
           "muted"=>ActiveModel::Type::Boolean.new.cast(clip["muted"]),"keyframes"=>frames,"has_audio"=>asset.metadata["has_audio"]==true||asset.kind=="audio"}
        end
        {"output"=>output,"width"=>width,"height"=>height,"clips"=>normalized.sort_by{|c|[c["track"],c["start"]]},"duration"=>normalized.map{|c|c["start"]+c["out"]-c["in"]}.max}
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
      def self.command(timeline, paths:, output:)
        args=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-filter_complex_threads","1"]
        timeline.fetch("clips").each_with_index do |clip,i|
          args+= ["-loop","1","-framerate","24"] if clip["kind"]=="image"
          args += ["-protocol_whitelist","file,pipe","-i",paths.fetch(i)]
        end
        duration=timeline.fetch("duration");filters=[];audio=[];video="base"
        if timeline["output"]=="video"
          filters<<"color=c=black:s=#{timeline['width']}x#{timeline['height']}:r=24:d=#{duration}[base]"
        end
        filters<<"anullsrc=r=48000:cl=stereo,atrim=duration=#{duration}[silence]";audio<<"[silence]"
        timeline["clips"].each_with_index do |clip,i|
          length=clip["out"]-clip["in"]
          if timeline["output"]=="video" && clip["kind"]!="audio"
            filters<<"[#{i}:v]trim=start=#{clip['in']}:end=#{clip['out']},setpts=PTS-STARTPTS+#{clip['start']}/TB,scale=#{timeline['width']}:#{timeline['height']}:force_original_aspect_ratio=decrease,setsar=1[v#{i}]"
            x=expression(clip["keyframes"],"x",clip["x"],start:clip["start"]);y=expression(clip["keyframes"],"y",clip["y"],start:clip["start"])
            filters<<"[#{video}][v#{i}]overlay=x='#{x}':y='#{y}':eof_action=pass:enable='between(t,#{clip['start']},#{clip['start']+length})'[layer#{i}]"
            video="layer#{i}"
          end
          if clip["has_audio"] && !clip["muted"]
            gain=expression(clip["keyframes"],"gain",clip["gain"])
            delay=(clip["start"]*1000).round
            filters<<"[#{i}:a]atrim=start=#{clip['in']}:end=#{clip['out']},asetpts=PTS-STARTPTS,volume='#{gain}':eval=frame,adelay=#{delay}|#{delay}[a#{i}]"
            audio<<"[a#{i}]"
          end
        end
        filters<<"#{audio.join}amix=inputs=#{audio.length}:duration=longest:normalize=0,alimiter=limit=0.95[aout]"
        args += ["-filter_complex",filters.join(';'),"-map","[aout]"]
        args += timeline["output"]=="video" ? ["-map","[#{video}]","-c:v","libx264","-pix_fmt","yuv420p","-preset","veryfast","-threads","2","-c:a","aac","-movflags","+faststart"] : ["-c:a","pcm_s16le"]
        args+["-t",duration.to_s,output]
      end
    end
  end
end
