# frozen_string_literal: true
module Studio
  module Performance
    # Two identities, ordered turns and reproducible direction; all renders and
    # checkout still belong to the existing CharacterScene operation.
    class DialogueScene < CharacterScene
      def self.start(access:,payload:)
        source=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless source.studio_project.site_id==access.site_id
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Use a dialogue request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        characters=payload.fetch("characters")
        turns=payload.fetch("turns")
        raise ArgumentError,"Choose exactly two characters" unless characters.is_a?(Array) && characters.size==2 && characters.all? { |row| row.is_a?(Hash) }
        sources=[]
        characters=characters.map do |row|
          name=row.fetch("name").to_s.strip
          raise ArgumentError,"Name each character using 1–60 characters" unless name.length.between?(1,60) && !name.include?("\0")
          voice=row.fetch("voice","en-us").to_s
          raise ArgumentError,"Choose en-us or en-gb for each voice" unless %w[en-us en-gb].include?(voice)
          colors=%w[skin wardrobe hair].to_h do |field|
            color=row.fetch(field,{"skin"=>"#925e43","wardrobe"=>"#344e78","hair"=>"#211916"}[field]).to_s
            raise ArgumentError,"Choose six-digit character colors" unless color.match?(/\A#[a-fA-F0-9]{6}\z/)
            [field,color]
          end
          result={"name"=>name,"voice"=>voice,"colors"=>colors}
          if row["cast_asset_id"].present?
            actor=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"blend",status:"ready").find(row["cast_asset_id"])
            profile=actor.metadata["character_profile"]
            raise ArgumentError,"Choose a registered Cast performer" unless actor.native.attached? && profile && profile["source_blob_id"]==actor.native.blob.id
            result.merge!("cast_asset_id"=>actor.id,"cast_profile"=>profile);sources<<actor.native.blob
          end
          result
        end
        raise ArgumentError,"Give the two characters different names" unless characters.map { |row| row["name"].downcase }.uniq.size==2
        raise ArgumentError,"Use two to four ordered speaking turns" unless turns.is_a?(Array) && turns.size.between?(2,4) && turns.all? { |row| row.is_a?(Hash) }
        turns=turns.map do |row|
          raise ArgumentError,"Choose character 1 or 2 for each turn" unless [0,1,"0","1"].include?(row["speaker"])
          speaker=Integer(row.fetch("speaker"));text=row.fetch("dialogue","").to_s.strip
          raise ArgumentError,"Choose character 1 or 2 for each turn" unless speaker.between?(0,1)
          raise ArgumentError,"Use up to 80 characters per spoken turn" unless text.length<=80 && !text.include?("\0")
          result={"speaker"=>speaker,"dialogue"=>text}
          if row["audio_asset_id"].present?
            audio=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"audio",status:"ready").find(row["audio_asset_id"])
            raise ArgumentError,"Use recordings lasting 0.2–2.8 seconds and at most 10 MB" unless audio.file.attached? && audio.file.blob.byte_size<=10.megabytes && audio.metadata["duration"].to_f.between?(0.2,2.8)
            result.merge!("audio_asset_id"=>audio.id,"audio_blob_id"=>audio.file.blob.id,"audio_duration"=>audio.metadata["duration"].to_f);sources<<audio.file.blob
          else
            raise ArgumentError,"Enter dialogue or choose a recording for every turn" if text.empty?
          end
          result
        end
        raise ArgumentError,"Give both characters at least one speaking turn" unless turns.map { |row| row["speaker"] }.uniq.size==2
        template=payload.fetch("scene_template","studio").to_s
        staging=SceneTemplates.snapshot(access:access,source:source,key:template)
        inputs={"mode"=>"dialogue","characters"=>characters,"turns"=>turns,"scene_template"=>template,"camera_mode"=>"dialogue"}
        operation=access.user.with_lock do
          scope=source.studio_project.studio_operations.where(capability:CAPABILITY).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'request_key' = ?",key).first
          if previous
            raise ArgumentError,"This key belongs to another performance" unless previous.studio_scene_id==source.id && previous.manifest["inputs"]==inputs && previous.manifest["staging"]==staging
            next previous
          end
          raise ArgumentError,"Wait for your current character scene" if scope.where(status:%w[pending running]).exists? || scope.where("created_at > ?",1.minute.ago).count>=3
          op=source.studio_operations.create!(studio_project:source.studio_project,production:source.production,operation_type:"character_scene",provider:"studio",capability:CAPABILITY,status:"pending",intent:{"user_id"=>access.user.id},manifest:{"inputs"=>inputs,"staging"=>staging},metadata:{"request_key"=>key,"phase"=>"queued","attempt"=>0,"deadline"=>10.minutes.from_now.iso8601})
          sources.uniq.each { |blob| op.performance_sources.attach(blob) };op
        end
        StudioCharacterSceneJob.perform_later(operation.id) if operation.status=="pending"
        receipt(access:access,id:operation.id)
      end

      def self.prepare(operation)
        access=check!(operation);inputs=operation.manifest.fetch("inputs");tag="dialogue-scene-#{operation.id}"
        operation.with_lock do
          unless operation.metadata["scene_id"]
            scene=operation.studio_project.studio_scenes.create!(production:operation.production,name:inputs["characters"].map { |row| row["name"] }.join(" & ")+" · dialogue",settings:StudioScene.default_settings.merge("render_engine"=>"CYCLES","compute_profile"=>"cpu_economy","resolution_x"=>640,"resolution_y"=>360,"samples"=>1,"fps"=>12,"frame_start"=>1,"frame_end"=>36,"world_color"=>[0.02,0.03,0.05,1]))
            SceneTemplates.apply!(scene,operation.manifest.fetch("staging"),access:access)
            operation.update!(metadata:operation.metadata.merge("scene_id"=>scene.id))
          end
        end
        scene=access.scene!(operation.metadata.fetch("scene_id"))
        actors=inputs.fetch("characters").each_with_index.map do |character,index|
          phase(operation,"building_character_#{index+1}")
          if character["cast_asset_id"]
            actor=StudioAsset.for_actor(access).find(character["cast_asset_id"])
            raise ArgumentError,"The reusable character changed. Start a new dialogue." unless actor.metadata["character_profile"]==character["cast_profile"] && actor.native.blob.id==character.dig("cast_profile","source_blob_id")
          else
            result=Cast.create(access:access,payload:character.fetch("colors").merge("name"=>character["name"],"style"=>"illustrated","request_key"=>"#{tag}-cast-#{index}"))
            actor=StudioAsset.find(result[:asset_id]);Cast.retry(access:access,payload:{"asset_id"=>actor.id}) if actor.status=="failed"
            actor.update!(metadata:actor.metadata.merge("performer_phase"=>"queued")) if actor.metadata["performer_phase"]=="building" && actor.updated_at<10.minutes.ago
            StudioCharacterCreateJob.perform_now(actor.id) unless actor.metadata["character_profile"]
          end
          raise Waiting,"Waiting for the character worker" unless actor.reload.status=="ready" && actor.metadata["character_profile"]
          raise ArgumentError,"The character source changed. Register its current version before preparing dialogue." unless actor.native.attached? && actor.native.blob.id==actor.metadata.dig("character_profile","source_blob_id")
          actor
        end
        phase(operation,"preparing_dialogue",{"cast_asset_ids"=>actors.map(&:id)})
        audio=inputs.fetch("turns").each_with_index.map do |turn,index|
          check!(operation)
          character=inputs["characters"][turn["speaker"]]
          prepare_audio(operation,access,character.merge(turn),"#{tag}-line-#{index}",scene)
        end
        time=0.35
        timing=audio.map do |asset|
          start=time;time+=asset.metadata.fetch("duration")+0.25
          {"start"=>start,"duration"=>asset.metadata.fetch("duration")}
        end
        seconds=(time+0.1).ceil
        raise ArgumentError,"Keep the complete conversation within eight seconds. Shorten a line or remove a turn." unless seconds<=8
        objects=actors.each_with_index.map do |actor,index|
          check!(operation)
          result=Cast.place(access:access,payload:{"scene_id"=>scene.id,"asset_id"=>actor.id,"lock_version"=>scene.reload.lock_version,"request_key"=>"#{tag}-place-#{index}"})
          object=scene.scene_objects.find(result.fetch("object_id"))
          unless object.definition["dialogue_initialized"]
            base=operation.manifest.dig("staging","actor_transform") || {"location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}
            center=base.fetch("location",[0,0,0]);location=[center[0]+(index==0 ? -1.0 : 1.0),center[1],center[2]]
            object.update!(name:inputs["characters"][index]["name"],definition:object.definition.merge("location"=>location,"rotation"=>[0,0,index==0 ? 10 : -10],"scale"=>[1,1,1],"dialogue_initialized"=>true,"dialogue_character"=>index))
          end
          object
        end
        phase(operation,"analyzing_speech")
        inputs.fetch("turns").each_with_index do |turn,index|
          check!(operation);object=objects[turn["speaker"]].reload;key="#{tag}-take-#{index}"
          next if scene.reload.settings.fetch("performance_receipts",{}).key?(key)
          analysis=LipSync.start(access:access,payload:{"scene_id"=>scene.id,"audio_asset_id"=>audio[index].id,"source_out"=>timing[index]["duration"],"dialogue"=>turn["dialogue"],"recognizer"=>"phonetic","request_key"=>"#{tag}-speech-#{index}-#{operation.metadata['attempt']}"})
          StudioLipSyncJob.perform_now(analysis[:id]);status=StudioOperation.find(analysis[:id]).status
          raise Waiting,"Waiting for speech analysis" if %w[pending running].include?(status)
          raise ArgumentError,"The speech worker could not analyze this turn" unless status=="completed"
          profile=actors[turn["speaker"]].metadata.fetch("character_profile");duration=timing[index]["duration"]
          expressions=profile.fetch("bindings").key?("brow_raise") ? [{"control"=>"brow_raise","start"=>0,"end"=>[duration,0.6].min,"value"=>0.2}] : []
          gestures=profile.fetch("bones").key?("head") ? [{"kind"=>"nod","start"=>0,"end"=>[duration,1.0].min,"strength"=>0.2}] : []
          Take.save(access:access,payload:{"scene_id"=>scene.id,"object_id"=>object.id,"lock_version"=>scene.reload.lock_version,"audio_asset_id"=>audio[index].id,"source_out"=>duration,"start"=>timing[index]["start"],"append"=>true,"lip_sync_mode"=>"phoneme","analysis_id"=>analysis[:id],"expressions"=>expressions,"gestures"=>gestures,"request_key"=>key})
        end
        phase(operation,"directing_conversation",{"duration_seconds"=>seconds,"dialogue_timing"=>timing})
        scene.with_lock do
          unless scene.settings["dialogue_scene_cameras"]
            objects.each_with_index do |object,index|
              reactions=inputs["turns"].each_with_index.filter_map do |turn,i|
                timing[i].merge("kind"=>"listen","speaker_object_id"=>objects[turn["speaker"]].id) unless turn["speaker"]==index
              end
              object.reload.update!(definition:object.definition.merge("listener_reactions"=>reactions))
            end
            center=objects.map { |object| object.definition["location"] }.transpose.map { |values| values.sum/2.0 }
            wide=scene.scene_objects.create!(name:"Dialogue two-shot",object_type:"camera",definition:{"location"=>[center[0],center[1]-6,center[2]+1.25],"look_at"=>[center[0],center[1],center[2]+1.25],"camera_type"=>"ORTHO","ortho_scale"=>6.8,"sensor_fit"=>"HORIZONTAL"})
            close=objects.each_with_index.map do |object,index|
              p=object.definition["location"]
              scene.scene_objects.create!(name:"#{inputs['characters'][index]['name']} · reverse",object_type:"camera",definition:{"location"=>[p[0]+(index==0 ? 0.45 : -0.45),p[1]-5,p[2]+1.8],"look_at"=>[p[0],p[1],p[2]+1.8],"camera_type"=>"ORTHO","ortho_scale"=>2.8,"sensor_fit"=>"HORIZONTAL"})
            end
            cuts=[{"camera_id"=>wide.id,"frame"=>1}]+inputs["turns"].each_with_index.map { |turn,i| {"camera_id"=>close[turn["speaker"]].id,"frame"=>1+(timing[i]["start"]*12).round} }
            presets=Array(scene.settings["blender_presets"]).deep_dup;presets.each { |preset| preset["camera_cuts"]=[] }
            scene.update!(settings:scene.settings.merge("frame_end"=>seconds*12,"camera_cuts"=>cuts,"active_camera_object_id"=>wide.id,"blender_presets"=>presets,"dialogue_scene_cameras"=>true,"dialogue_timing"=>timing,"native_revision"=>scene.settings.fetch("native_revision",0)+1))
          end
        end
        phase(operation,"rendering_preview")
        preview=scene.studio_operations.find_by(id:operation.metadata["preview_id"])
        unless preview
          result=Studio::Workers::Workspace.perform("performance_preview",{"user_id"=>access.user.id,"site_id"=>access.site_id,"scene_id"=>scene.id,"scene_playback"=>true,"preview_seconds"=>seconds})
          preview=scene.studio_operations.find(result[:operation_id]);phase(operation,"rendering_preview",{"preview_id"=>preview.id})
        end
        preview.update!(status:"pending",error_message:nil) if preview.status=="failed"
        StudioBlenderPreviewJob.perform_now(preview.id) unless preview.status=="completed"
        raise Waiting,"Waiting for the preview worker" if %w[pending running].include?(preview.reload.status)
        raise ArgumentError,"The dialogue preview did not finish" unless preview.status=="completed" && preview.artifacts.exists?(kind:"video")
        operation.with_lock { check!(operation);operation.update!(status:"completed",completed_at:Time.current,metadata:operation.metadata.merge("phase"=>"ready")) }
      end
    end
  end
end
