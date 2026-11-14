# frozen_string_literal: true
require "json"
require "fileutils"
module Studio
  module Performance
    class LipSync
      SHAPES = %w[A B C D E F G H X].freeze
      VERSION = "1.14.0"
      def self.cues(raw, duration:)
        raise ArgumentError,"Use 1–1024 mouth cues" unless raw.is_a?(Array) && raw.length.between?(1,1024)
        previous=0.0
        raw.map do |cue|
          first=Take.number(cue.fetch("start"),0,duration)
          last=Take.number(cue.fetch("end"),0,duration)
          shape=cue.fetch("value").to_s
          raise ArgumentError,"Mouth cues must be ordered, non-overlapping and use A–H or X" unless first>=previous && last>first && SHAPES.include?(shape)
          previous=last
          {"start"=>first,"end"=>last,"value"=>shape}
        end
      end
      def self.call(blob, first:, duration:, recognizer:, dialogue:)
        raise ArgumentError,"Choose English speech or phonetic recognition" unless %w[pocketSphinx phonetic].include?(recognizer)
        raise ArgumentError,"Dialogue is limited to 4000 characters" if dialogue.length>4000 || dialogue.include?("\x00")
        blob.open do |source|
          Studio::MediaProcess.temporary_directory("lightek-lipsync-") do |root|
            input=File.join(root,"source#{File.extname(blob.filename.to_s)}");FileUtils.cp(source.path,input)
            wav=File.join(root,"speech.wav");text=File.join(root,"dialogue.txt");File.write(text,dialogue)
            ffmpeg=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-protocol_whitelist","file,pipe","-ss",first.to_s,"-i",input,"-t",duration.to_s,"-vn","-ac","1","-ar","16000",wav]
            rhubarb=[Rails.env.production? ? "/opt/rhubarb/rhubarb" : ENV.fetch("LIGHTEK_RHUBARB","rhubarb"),"-f","json","-r",recognizer,"--extendedShapes","GHX","--threads","1"]
            rhubarb += ["--dialogFile",text] if dialogue.present?
            rhubarb << wav
            [[rhubarb.first,"--version"],ffmpeg,rhubarb].each_with_index.map do |command,index|
              if Rails.env.production?
                command=command.map{|value|value.gsub(root,"/work")}
                command=Studio::MediaProcess.container(command,root:root,image:Studio::NativeBlender::Runtime.image(:media))
              end
              output=Studio::MediaProcess.run!(command,timeout:[8,45,180].fetch(index))
              if index==0
                raise ArgumentError,"Install the pinned Rhubarb speech engine version" unless output.strip=="Rhubarb Lip Sync version #{VERSION}"
              end
              next unless index==2
              result=JSON.parse(output)
              measured=Float(result.fetch("metadata").fetch("duration"))
              raise ArgumentError,"The speech engine returned an invalid duration" unless measured.finite? && (measured-duration).abs<=0.15
              {"engine"=>"rhubarb","version"=>VERSION,"recognizer"=>recognizer,"duration"=>duration,
                "cues"=>cues(result.fetch("mouthCues"),duration:duration+0.015).map{|cue|cue.merge("end"=>[cue["end"],duration].min)}.select{|cue|cue["end"]>cue["start"]}}
            end.last
          end
        end
      end
      def self.start(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        audio=StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready",kind:%w[audio video]).find(payload.fetch("audio_asset_id"))
        raise ArgumentError,"Choose a recording containing audio" unless audio.file.attached? && (audio.kind=="audio" || audio.metadata["has_audio"])
        first=Take.number(payload.fetch("source_in",0),0,7200);last=Take.number(payload.fetch("source_out"),0,7200)
        raise ArgumentError,"Analyze 0.1–30 seconds within the recording" unless (last-first).between?(0.1,30) && last<=audio.metadata["duration"].to_f+0.01
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A speech request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        recognizer=payload.fetch("recognizer","pocketSphinx").to_s;dialogue=payload.fetch("dialogue","").to_s.strip
        raise ArgumentError,"Invalid speech recognizer or dialogue" unless %w[pocketSphinx phonetic].include?(recognizer) && dialogue.length<=4000 && !dialogue.include?("\x00")
        intent={"user_id"=>access.user.id,"audio_asset_id"=>audio.id,"audio_blob_id"=>audio.file.blob.id,"source_in"=>first,"duration"=>last-first,"recognizer"=>recognizer,"dialogue"=>dialogue,"request_key"=>key}
        operation=nil
        scene.with_lock do
          operation=scene.studio_operations.where(operation_type:"speech_analysis").where("intent ->> 'request_key' = ?",key).find{|op|op.intent["user_id"]==access.user.id}
          if operation
            raise ArgumentError,"This speech request key belongs to another recording" unless operation.intent==intent
          else
            pending=scene.studio_operations.where(operation_type:"speech_analysis",status:%w[pending running]).count
            raise ArgumentError,"Wait for this scene's speech analysis to finish" if pending>=2
            operation=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"speech_analysis",provider:"rhubarb",capability:"studio.workspace.performance.analyze",status:"pending",intent:intent)
            operation.performance_sources.attach(audio.file.blob)
            StudioLipSyncJob.perform_later(operation.id)
          end
        end
        receipt(operation)
      end
      def self.find(access:,scene:,id:)
        operation=scene.studio_operations.where(operation_type:"speech_analysis").find(id)
        raise ActiveRecord::RecordNotFound unless operation.intent["user_id"]==access.user.id && scene.studio_project.site_id.to_i==access.site_id.to_i
        operation
      end
      def self.receipt(operation)
        {id:operation.id,status:operation.status,error:operation.error_message,result:operation.status=="completed" ? operation.manifest["lip_sync"] : nil}
      end
    end
  end
end
