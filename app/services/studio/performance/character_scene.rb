# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class CharacterScene
      class Waiting < StandardError; end
      CAPABILITY="studio.workspace.character.scene.prepare"
      def self.start(access:,payload:)
        return DialogueScene.start(access:access,payload:payload) if payload["mode"]=="dialogue"
        raise ArgumentError,"Choose single or dialogue mode" if payload["mode"].present? && payload["mode"]!="single"
        source=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless source.studio_project.site_id==access.site_id
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Use a character-scene request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        name=payload.fetch("name","Sentinel").to_s.strip
        text=payload.fetch("dialogue","").to_s.strip
        raise ArgumentError,"Name the character using 1–60 characters" unless name.length.between?(1,60)
        raise ArgumentError,"Use a short line of dialogue, up to 80 characters" unless text.length<=80 && !text.include?("\0")
        voice=payload.fetch("voice","en-us").to_s
        raise ArgumentError,"Choose the stock en-us or en-gb voice" unless %w[en-us en-gb].include?(voice)
        colors=%w[skin wardrobe hair].to_h do |field|
          color=payload.fetch(field,{"skin"=>"#925e43","wardrobe"=>"#344e78","hair"=>"#211916"}[field]).to_s
          raise ArgumentError,"Choose six-digit colors" unless color.match?(/\A#[a-fA-F0-9]{6}\z/)
          [field,color]
        end
        template_key=payload.fetch("scene_template","studio").to_s
        camera_mode=payload.fetch("camera_mode","character").to_s
        gesture=payload.fetch("gesture",(payload["mechanics"].present? || payload["contact"].present? || %w[point_left point_right].include?(payload["body_action"])) ? "still" : SceneTemplates.defaults(template_key)["gesture"]).to_s
        raise ArgumentError,"Choose character coverage or template cameras" unless SceneTemplates::CAMERA_MODES.include?(camera_mode)
        raise ArgumentError,"Choose an available starter action" unless SceneTemplates::GESTURES.include?(gesture)
        staging=SceneTemplates.snapshot(access:access,source:source,key:template_key)
        inputs={"name"=>name,"dialogue"=>text,"voice"=>voice,"colors"=>colors,"scene_template"=>template_key,"camera_mode"=>camera_mode,"gesture"=>gesture}.merge(Acting.inputs(payload)).merge(Contact.inputs(payload)).merge(Mechanics.inputs(payload)).merge(Attention.inputs(payload))
        Contact.validate_target!(inputs,staging)
        Mechanics.validate!(inputs,staging)
        Attention.validate!(inputs,staging)
        Acting.gesture!(inputs)
        audio=nil;actor=nil
        if payload["audio_asset_id"].present?
          audio=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"audio",status:"ready").find(payload["audio_asset_id"])
          raise ArgumentError,"Use a recording lasting 0.2–2.8 seconds for this first short scene" unless audio.file.attached? && audio.file.blob.byte_size<=10.megabytes && audio.metadata["duration"].to_f.between?(0.2,2.8)
          inputs.merge!("audio_asset_id"=>audio.id,"audio_blob_id"=>audio.file.blob.id,"audio_duration"=>audio.metadata["duration"].to_f)
        else
          raise ArgumentError,"Enter a short spoken line or choose a recording" if text.empty?
        end
        if payload["cast_asset_id"].present?
          actor=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"blend",status:"ready").find(payload["cast_asset_id"])
          profile=actor.metadata["character_profile"]
          raise ArgumentError,"Choose a registered Cast performer" unless actor.native.attached? && profile && profile["source_blob_id"]==actor.native.blob.id
          Contact.validate_profile!(inputs,profile)
          Mechanics.validate_profile!(inputs,profile)
          Attention.validate_profile!(inputs,profile)
          inputs.merge!("cast_asset_id"=>actor.id,"cast_profile"=>profile)
        end
        operation=access.user.with_lock do
          scope=source.studio_project.studio_operations.where(capability:CAPABILITY).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'request_key' = ?",key).first
          if previous
            raise ArgumentError,"This request key belongs to another character scene" unless previous.studio_scene_id==source.id && previous.manifest["inputs"]==inputs && previous.manifest["staging"]==staging
            next previous
          end
          raise ArgumentError,"Wait for your current character scene" if scope.where(status:%w[pending running]).exists? || scope.where("created_at > ?",1.minute.ago).count>=3
          op=source.studio_operations.create!(studio_project:source.studio_project,production:source.production,operation_type:"character_scene",provider:"studio",capability:CAPABILITY,status:"pending",intent:{"user_id"=>access.user.id},manifest:{"inputs"=>inputs,"staging"=>staging},metadata:{"request_key"=>key,"phase"=>"queued","attempt"=>0,"deadline"=>10.minutes.from_now.iso8601})
          op.performance_sources.attach(audio.file.blob) if audio
          op.performance_sources.attach(actor.native.blob) if actor
          op
        end
        StudioCharacterSceneJob.perform_later(operation.id) if operation.status=="pending"
        receipt(access:access,id:operation.id)
      end
      def self.find(access,id)
        operation=StudioOperation.where(capability:CAPABILITY,studio_project_id:access.projects.where(site_id:access.site_id).select(:id)).find(id)
        raise ActiveRecord::RecordNotFound unless operation.intent["user_id"]==access.user.id
        operation
      end
      def self.latest(access:,scene_id:)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        operation=scene.studio_operations.where(capability:CAPABILITY).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s).order(id: :desc).first
        operation ? receipt(access:access,id:operation.id) : {status:"idle"}
      end
      def self.receipt(access:,id:)
        operation=find(access,id)
        child=operation.studio_project.studio_operations.find_by(id:operation.metadata["preview_id"])
        artifact=child&.status=="completed" && child.artifacts.find_by(kind:"video")
        {operation_id:operation.id,inputs:operation.manifest["inputs"].slice("name","dialogue","voice","colors","cast_asset_id","audio_asset_id","scene_template","camera_mode","gesture","mode","characters","turns","emotion","body_action","entrance","contact","mechanics","attention"),status:operation.status,phase:operation.metadata["phase"],error:operation.error_message,
          scene_id:operation.metadata["scene_id"],cast_asset_id:operation.metadata["cast_asset_id"],cast_asset_ids:operation.metadata["cast_asset_ids"],duration_seconds:operation.metadata["duration_seconds"],turn_timing:operation.metadata["dialogue_timing"],preview_operation_id:child&.id,
          url:artifact && artifact.file.attached? ? Rails.application.routes.url_helpers.rails_blob_path(artifact.file,only_path:true) : nil}.compact
      end
      def self.retry(access:,id:)
        operation=find(access,id)
        operation.with_lock do
          raise ArgumentError,"Only failed preparations can retry" unless operation.status=="failed"
          operation.update!(status:"pending",error_message:nil,completed_at:nil,metadata:operation.metadata.merge("attempt"=>operation.metadata.fetch("attempt",0)+1,"deadline"=>10.minutes.from_now.iso8601))
        end
        StudioCharacterSceneJob.perform_later(operation.id)
        receipt(access:access,id:id)
      end
      def self.quote(access:,payload:)
        operation=find(access,payload.fetch("operation_id"))
        raise ArgumentError,"Finish and review the character preview first" unless operation.status=="completed"
        scene=access.scene!(operation.metadata.fetch("scene_id"))
        operation.with_lock do
          scene.with_lock do
            signature=Digest::SHA256.hexdigest(Blender::ManifestBuilder.new(scene).call.to_json)
            previous=scene.studio_operations.find_by(id:operation.metadata["export_id"])
            if previous && operation.metadata["export_signature"]==signature
              return {operation_id:previous.id,status:previous.status,quote:previous.cost_quote,operation_type:previous.operation_type}
            end
            result=Studio::Workers::Workspace.perform("render_quote",{"user_id"=>access.user.id,"site_id"=>access.site_id,"scene_id"=>scene.id})
            operation.update!(metadata:operation.metadata.merge("export_id"=>result[:operation_id],"export_signature"=>signature))
            result
          end
        end
      end
      def self.check!(operation)
        raise ArgumentError,"This character preparation is no longer active" unless operation.reload.status=="running"
        access=Studio::PwaAccess.new("user_id"=>operation.intent.fetch("user_id"),"site_id"=>operation.studio_project.site_id)
        find(access,operation.id)
        LightekPwa::Policy.new(user:access.user,site:operation.studio_project.site).authorize!("studio")
        LightekPwa::Network.require_studio_write!(user:access.user,site:operation.studio_project.site,capability:CAPABILITY) if defined?(LightekPwa::Network)
        access
      end
      def self.phase(operation,name,values={})
        check!(operation)
        operation.update!(metadata:operation.metadata.merge(values).merge("phase"=>name))
      end
      # Shared by one-performer studies and bounded dialogue scenes. Source blobs
      # are frozen on the parent operation before a background worker runs.
      def self.prepare_audio(operation,access,inputs,tag,scene)
        audio=StudioAsset.find_by(owner:access.user,request_key:tag+"-voice")
        unless audio&.file&.attached?
          Studio::MediaProcess.temporary_directory("character-voice-") do |root|
            file=File.join(root,"voice.wav")
            if inputs["audio_blob_id"]
              blob=operation.performance_sources.blobs.find(inputs["audio_blob_id"])
              input=File.join(root,"recording-source")
              blob.open { |source| FileUtils.cp(source.path,input) }
              duration=inputs.fetch("audio_duration")
              command=["ffmpeg","-v","error","-y","-protocol_whitelist","file,pipe","-i",input,"-t",duration.to_s,"-vn","-ac","1","-ar","22050",file]
              command=Studio::MediaProcess.container(command.map { |part| part.sub(root,"/work") },root:root,image:Studio::NativeBlender::Runtime.image(:media)) if Rails.env.production?
              Studio::MediaProcess.run!(command,timeout:30)
            else
              ScreenplayEngine::AudioSynthesizer.synthesize!(text:inputs.fetch("dialogue"),path:file,voice:inputs["voice"],speed:180)
              command=["ffprobe","-v","error","-show_entries","format=duration","-of","json",file]
              command=Studio::MediaProcess.container(command.map { |part| part.sub(root,"/work") },root:root,image:Studio::NativeBlender::Runtime.image(:media)) if Rails.env.production?
              duration=Float(JSON.parse(Studio::MediaProcess.run!(command,timeout:20)).fetch("format").fetch("duration"))
            end
            raise ArgumentError,"Use a shorter line or recording lasting 0.2–2.8 seconds" unless duration.finite? && duration.between?(0.2,2.8)
            audio=StudioAsset.new(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,name:inputs["name"]+" · dialogue",kind:"audio",status:"ready",request_key:tag+"-voice",metadata:{"duration"=>duration,"has_audio"=>true,"synthetic_voice"=>!inputs["audio_blob_id"],"transcript"=>inputs["dialogue"]})
            audio.file.attach(io:File.open(file),filename:"dialogue.wav",content_type:"audio/wav",identify:false);audio.save!
          end
        end
        audio
      end
      def self.prepare(operation)
        return DialogueScene.prepare(operation) if operation.manifest.dig("inputs","mode")=="dialogue"
        access=check!(operation);inputs=operation.manifest.fetch("inputs");tag="character-scene-#{operation.id}"
        operation.with_lock do
          unless operation.metadata["scene_id"]
            scene=operation.studio_project.studio_scenes.create!(production:operation.production,name:"#{inputs['name']} · performed short",settings:StudioScene.default_settings.merge("render_engine"=>"CYCLES","compute_profile"=>"cpu_economy","resolution_x"=>640,"resolution_y"=>360,"samples"=>1,"fps"=>12,"frame_start"=>1,"frame_end"=>36,"world_color"=>[0.02,0.03,0.05,1]))
            SceneTemplates.apply!(scene,operation.manifest.fetch("staging"),access:access)
            operation.update!(metadata:operation.metadata.merge("scene_id"=>scene.id))
          end
        end
        scene=access.scene!(operation.metadata.fetch("scene_id"))
        phase(operation,"building_character")
        if inputs["cast_asset_id"]
          actor=StudioAsset.for_actor(access).find(inputs["cast_asset_id"])
          raise ArgumentError,"The reusable character changed. Start a new scene using its current version." unless actor.metadata["character_profile"]==inputs["cast_profile"]
        else
          result=Cast.create(access:access,payload:inputs.fetch("colors").merge("name"=>inputs["name"],"style"=>"illustrated","request_key"=>tag+"-cast"))
          actor=StudioAsset.find(result[:asset_id])
          Cast.retry(access:access,payload:{"asset_id"=>actor.id}) if actor.status=="failed"
          if actor.metadata["performer_phase"]=="building" && actor.updated_at<10.minutes.ago
            actor.update!(metadata:actor.metadata.merge("performer_phase"=>"queued"))
          end
          StudioCharacterCreateJob.perform_now(actor.id) unless actor.metadata["character_profile"]
        end
        raise Waiting,"Waiting for the character worker" unless actor.reload.status=="ready" && actor.metadata["character_profile"]
        Acting.validate!(inputs,actor.metadata.fetch("character_profile"))
        Contact.validate_profile!(inputs,actor.metadata.fetch("character_profile"))
        Mechanics.validate_profile!(inputs,actor.metadata.fetch("character_profile"))
        Attention.validate_profile!(inputs,actor.metadata.fetch("character_profile"))
        phase(operation,"preparing_dialogue",{"cast_asset_id"=>actor.id})
        audio=prepare_audio(operation,access,inputs,tag,scene)
        phase(operation,"analyzing_speech")
        placement=Cast.place(access:access,payload:{"scene_id"=>scene.id,"asset_id"=>actor.id,"lock_version"=>scene.reload.lock_version,"request_key"=>tag+"-place"})
        object=scene.scene_objects.find(placement.fetch("object_id"))
        unless object.definition["template_performer_initialized"]
          source=operation.manifest.fetch("staging")
          definition=object.definition.merge(source.fetch("actor_transform",{}))
          motion=source["actor_motion"]
          definition["motion_clips"]=motion["motion_clips"] if motion && motion["asset_id"]==actor.id && motion["character_profile"]==actor.metadata["character_profile"]
          object.update!(definition:definition.merge("template_performer_initialized"=>true))
        end
        unless object.definition["performance"]
          analysis=LipSync.start(access:access,payload:{"scene_id"=>scene.id,"audio_asset_id"=>audio.id,"source_out"=>audio.metadata.fetch("duration"),"dialogue"=>inputs["dialogue"],"recognizer"=>"phonetic","request_key"=>tag+"-speech-#{operation.metadata['attempt']}"})
          StudioLipSyncJob.perform_now(analysis[:id])
          analysis_status=StudioOperation.find(analysis[:id]).status
          raise Waiting,"Waiting for speech analysis" if %w[pending running].include?(analysis_status)
          raise ArgumentError,"The speech worker could not analyze this recording" unless analysis_status=="completed"
          duration=audio.metadata.fetch("duration")
          expressions=Acting.expressions(inputs,actor.metadata.fetch("character_profile"),duration)
          kind=inputs.fetch("gesture");binding={"wave_right"=>"right_arm","nod"=>"head","shake"=>"head"}[kind]
          gestures=binding && actor.metadata.dig("character_profile","bones").key?(binding) ? [{"kind"=>kind,"start"=>0,"end"=>duration,"strength"=>0.45}] : []
          Take.save(access:access,payload:{"scene_id"=>scene.id,"object_id"=>object.id,"lock_version"=>scene.reload.lock_version,"audio_asset_id"=>audio.id,"source_out"=>duration,"start"=>(inputs["mechanics"] ? Mechanics.speech_start(inputs) : inputs.fetch("entrance","none")=="none" ? 0.1 : 1.0),"lip_sync_mode"=>"phoneme","analysis_id"=>analysis[:id],"expressions"=>expressions,"gestures"=>gestures,"request_key"=>tag+"-take"})
        end
        take=object.reload.definition.fetch("performance")
        Acting.apply!(access:access,scene:scene,object:object,character:inputs,turns:[take],key:tag+"-acting")
        Contact.apply!(scene:scene,object:object,character:inputs)
        Mechanics.apply!(scene:scene,object:object,character:inputs)
        seconds=[inputs["mechanics"] ? 8 : 3,(take["start"]+take["duration"]+0.1).ceil,Contact.ending(inputs).ceil,Attention.ending(inputs).ceil].max
        scene.with_lock { scene.update!(settings:scene.settings.merge("frame_end"=>seconds*12)) } unless scene.reload.settings["frame_end"]==seconds*12
        phase(operation,"directing_cameras")
        unless scene.reload.settings["character_scene_cameras"]
          scene.with_lock do
            cameras=scene.scene_objects.where(object_type:"camera").order(:position,:id).to_a
            if inputs["camera_mode"]=="template" && cameras.any?
              cuts=scene.settings["camera_cuts"].presence || cameras.first(2).each_with_index.map { |camera,index| {"camera_id"=>camera.id,"frame"=>index==0 ? 1 : 19} }
              first=cameras.find { |camera| camera.id==cuts.first["camera_id"] } || cameras.first
              settings={"camera_cuts"=>cuts,"active_camera_object_id"=>first.id}
            else
              location=object.definition.fetch("location",[0,0,0])
              wide=scene.scene_objects.create!(name:"Character wide",object_type:"camera",definition:{"location"=>[location[0],location[1]-5,location[2]+1.2],"look_at"=>[location[0],location[1],location[2]+1.2],"camera_type"=>"ORTHO","sensor_fit"=>"HORIZONTAL","ortho_scale"=>5.2})
              close=scene.scene_objects.create!(name:"Character close",object_type:"camera",definition:{"location"=>[location[0],location[1]-5,location[2]+(inputs["contact"] ? 1.55 : 1.85)],"look_at"=>[location[0],location[1],location[2]+(inputs["contact"] ? 1.55 : 1.85)],"camera_type"=>"ORTHO","sensor_fit"=>"HORIZONTAL","ortho_scale"=>(inputs["contact"] ? 3.6 : 2.5)})
              settings={"camera_cuts"=>(inputs["mechanics"] ? [{"camera_id"=>wide.id,"frame"=>1}] : [{"camera_id"=>wide.id,"frame"=>1},{"camera_id"=>close.id,"frame"=>19}]),"active_camera_object_id"=>wide.id}
            end
            scene.update!(settings:scene.settings.merge(settings).merge("character_scene_cameras"=>true,"native_revision"=>scene.settings.fetch("native_revision",0)+1))
          end
        end
        Attention.apply!(scene:scene,object:object,character:inputs)
        phase(operation,"rendering_preview")
        preview=scene.studio_operations.find_by(id:operation.metadata["preview_id"])
        unless preview
          result=Studio::Workers::Workspace.perform("performance_preview",{"user_id"=>access.user.id,"site_id"=>access.site_id,"scene_id"=>scene.id,"scene_playback"=>true,"preview_seconds"=>seconds})
          preview=scene.studio_operations.find(result[:operation_id]);phase(operation,"rendering_preview",{"preview_id"=>preview.id})
        end
        preview.update!(status:"pending",error_message:nil) if preview.status=="failed"
        StudioBlenderPreviewJob.perform_now(preview.id) unless preview.status=="completed"
        raise Waiting,"Waiting for the preview worker" if %w[pending running].include?(preview.reload.status)
        raise ArgumentError,"The character preview did not finish" unless preview.status=="completed" && preview.artifacts.exists?(kind:"video")
        operation.with_lock do
          check!(operation);operation.update!(status:"completed",completed_at:Time.current,metadata:operation.metadata.merge("phase"=>"ready"))
        end
      end
    end
  end
end
