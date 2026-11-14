# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class Take
      def self.number(value,min,max)
        n=Float(value);raise ArgumentError,"Performance timing or value is outside its range" unless n.finite? && n.between?(min,max);n
      end
      def self.save(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        object=scene.scene_objects.find(payload.fetch("object_id"))
        profile=object.definition["character_profile"] || raise(ArgumentError,"Select a character placed from Cast")
        audio=StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready",kind:%w[audio video]).find(payload.fetch("audio_asset_id"))
        raise ArgumentError,"Choose an asset containing audio" unless audio.kind=="audio" || audio.metadata["has_audio"]
        first=number(payload.fetch("source_in",0),0,7200);last=number(payload.fetch("source_out"),0,7200);start=number(payload.fetch("start",0),0,600)
        duration=last-first
        raise ArgumentError,"Use a performance of 0.1–30 seconds within the source recording" unless duration.between?(0.1,30) && last<=audio.metadata["duration"].to_f+0.01 && start+duration<=600
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A take request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        fingerprint=Digest::SHA256.hexdigest(payload.to_h.except("request_key","lock_version","user_id","site_id","origin").to_json)
        existing=scene.settings.fetch("performance_receipts",{})[key]
        if existing
          raise ArgumentError,"This take request key belongs to different direction" unless existing["fingerprint"]==fingerprint
          return existing
        end
        expressions=Array(payload["expressions"])
        gestures=Array(payload["gestures"])
        raise ArgumentError,"Use at most 64 expression and 32 gesture cues" if expressions.length>64 || gestures.length>32
        expressions=expressions.map do |cue|
          control=cue.fetch("control");raise ArgumentError,"Bind this face control in Cast first" unless profile["bindings"].key?(control)
          a=number(cue.fetch("start"),0,duration);b=number(cue.fetch("end"),0,duration)
          raise ArgumentError,"Expression end must follow start" unless b>a
          {"control"=>control,"start"=>a,"end"=>b,"value"=>number(cue.fetch("value",1),0,1)}
        end
        gestures=gestures.map do |cue|
          kind=cue.fetch("kind");binding={"nod"=>"head","shake"=>"head","wave_left"=>"left_arm","wave_right"=>"right_arm"}[kind]
          raise ArgumentError,"Bind the required gesture bone in Cast first" unless binding && profile["bones"][binding]
          a=number(cue.fetch("start"),0,duration);b=number(cue.fetch("end"),0,duration)
          raise ArgumentError,"Gesture end must follow start" unless b>a
          {"kind"=>kind,"start"=>a,"end"=>b,"strength"=>number(cue.fetch("strength",0.5),0,1)}
        end
        expressions.group_by { |cue| cue["control"] }.each_value do |cues|
          raise ArgumentError,"Expression cues on the same control cannot overlap" if cues.sort_by { |cue| cue["start"] }.each_cons(2).any? { |a,b| a["end"]>b["start"] }
        end
        gestures.group_by { |cue| cue["kind"].start_with?("wave") ? cue["kind"] : "head" }.each_value do |cues|
          raise ArgumentError,"Gestures on the same bone cannot overlap" if cues.sort_by { |cue| cue["start"] }.each_cons(2).any? { |a,b| a["end"]>b["start"] }
        end
        mode=payload.fetch("lip_sync_mode","volume").to_s
        raise ArgumentError,"Choose volume or phoneme mouth animation" unless %w[volume phoneme].include?(mode)
        lip_sync=nil
        if mode=="phoneme"
          saved=object.definition["performance"].to_h
          analysis_id=Integer(payload.fetch("analysis_id"))
          if saved.dig("lip_sync","analysis_id")==analysis_id && saved.values_at("audio_asset_id","audio_blob_id","source_in","duration")==[audio.id,audio.file.blob.id,first,duration]
            data=saved.fetch("lip_sync")
          else
            analysis=LipSync.find(access:access,scene:scene,id:analysis_id)
            raise ArgumentError,"Finish speech analysis for this recording and trim first" unless analysis.status=="completed" && analysis.intent.values_at("audio_asset_id","audio_blob_id","source_in","duration")==[audio.id,audio.file.blob.id,first,duration]
            data=analysis.manifest.fetch("lip_sync").merge("dialogue"=>analysis.intent["dialogue"])
          end
          lip_sync=data.slice("engine","version","recognizer","dialogue").merge("analysis_id"=>analysis_id,
            "cues"=>LipSync.cues(payload.fetch("mouth_cues",data.fetch("cues")),duration:duration))
        end
        envelope=mode=="volume" ? AudioEnvelope.call(audio,first:first,duration:duration) : []
        result=nil
        scene.with_lock do
          receipts=scene.settings.fetch("performance_receipts",{})
          if receipts[key]
            raise ArgumentError,"This take key belongs to different direction" unless receipts[key]["fingerprint"]==fingerprint
            return receipts[key]
          end
          scene.lock_version=Integer(payload.fetch("lock_version"));object.reload
          object.update!(definition:object.definition.merge("performance"=>{"take_id"=>key,"audio_asset_id"=>audio.id,"audio_blob_id"=>audio.file.blob.id,
            "source_in"=>first,"duration"=>duration,"start"=>start,"gain"=>number(payload.fetch("gain",1),0,4),"mouth_frames"=>envelope,"lip_sync_mode"=>mode,"lip_sync"=>lip_sync,"expressions"=>expressions,"gestures"=>gestures}))
          fps=scene.settings.fetch("fps",24).to_f/scene.settings.fetch("fps_base",1)
          ending=((start+duration)*fps).ceil
          result={"scene_id"=>scene.id,"object_id"=>object.id,"lock_version"=>scene.lock_version+1,"duration"=>duration,"fingerprint"=>fingerprint}
          scene.update!(settings:scene.settings.merge("frame_start"=>1,"frame_end"=>[scene.settings.fetch("frame_end",1),ending].max,"frame_current"=>1,"native_revision"=>scene.settings.fetch("native_revision",0).to_i+1,
            "performance_receipts"=>receipts.to_a.last(99).to_h.merge(key=>result)))
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed while preparing the take. Refresh and try again."
      end
      def self.remove(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"));scene.with_lock do
          scene.lock_version=Integer(payload.fetch("lock_version"))
          object=scene.scene_objects.find(payload.fetch("object_id"));object.update!(definition:object.definition.except("performance"))
          scene.update!(settings:scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0).to_i+1))
        end
        {scene_id:scene.id,lock_version:scene.lock_version}
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before removing the take."
      end
    end
  end
end
