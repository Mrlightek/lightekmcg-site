# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class SceneTemplates
      LAUNCH_CAPABILITY="studio.workspace.character.template.use"
      GESTURES=%w[wave_right nod shake still].freeze
      CAMERA_MODES=%w[character template].freeze
      HANDOFF_KEY="counter_handoff"
      def self.counter_handoff
        [
          {"id"=>"parcel","name"=>"Exchange parcel","type"=>"cube","definition"=>{
            "location"=>[-0.18,-0.32,1.16],"scale"=>[0.095,0.08,0.125],
            "material"=>{"color"=>[0.68,0.30,0.07]},"contact_response"=>"counter_handoff"}},
          {"id"=>"counter","name"=>"Exchange counter","type"=>"cube","definition"=>{
            "location"=>[0,-0.32,1.005],"scale"=>[0.55,0.07,0.03],
            "material"=>{"color"=>[0.06,0.13,0.18]}}},
          {"id"=>"stand","name"=>"Counter pedestal","type"=>"cube","definition"=>{
            "location"=>[0,-0.32,0.4875],"scale"=>[0.16,0.065,0.4875],
            "material"=>{"color"=>[0.045,0.09,0.13]}}}
        ]
      end

      def self.control_panel
        [{"id"=>"panel","name"=>"Control panel","type"=>"cube","definition"=>{"location"=>[0.78,0.05,1.2],"scale"=>[0.16,0.12,0.24],"material"=>{"color"=>[0.09,0.16,0.24]}}},
         {"id"=>"button","name"=>"Activation button","type"=>"cube","definition"=>{"location"=>[0.78,-0.095,1.2],"scale"=>[0.08,0.025,0.08],"material"=>{"color"=>[0.05,0.65,0.8]},"contact_response"=>"button_press"}},
         {"id"=>"stand","name"=>"Panel stand","type"=>"cube","definition"=>{"location"=>[0.78,0.1,0.5],"scale"=>[0.06,0.06,0.5],"material"=>{"color"=>[0.12,0.16,0.20]}}}]
      end
      def self.bench
        [{"id"=>"ground","name"=>"Bench ground","type"=>"plane","definition"=>{"location"=>[0,0,0],"scale"=>[4,4,1],"material"=>{"color"=>[0.045,0.065,0.08]}}},{"id"=>"seat","name"=>"Bench seat","type"=>"cube","definition"=>{"location"=>[0,0.27,0.40],"scale"=>[0.8,0.19,0.04],"mechanics_seat"=>1,"material"=>{"color"=>[0.30,0.16,0.07]}}},
         {"id"=>"back","name"=>"Bench back","type"=>"cube","definition"=>{"location"=>[0,0.50,0.72],"scale"=>[0.8,0.035,0.26],"material"=>{"color"=>[0.30,0.16,0.07]}}},
         *[-0.6,0.6].map.with_index { |x,i| {"id"=>"bench_leg_#{i}","name"=>"Bench leg #{i+1}","type"=>"cube","definition"=>{"location"=>[x,0.29,0.18],"scale"=>[0.04,0.13,0.18],"material"=>{"color"=>[0.09,0.10,0.12]}}} }]
      end
      def self.recipes
        Studio::Library::Catalog.items.select { |row| row["target"]=="scene" && !%w[characters fx].include?(row["category"]) }
      end
      def self.defaults(key)
        interview=key.match?(/interview|broadcast/)
        {"name"=>interview ? "Host" : "Sentinel","dialogue"=>interview ? "Welcome to the conversation." : "We protect this city.",
          "gesture"=>interview ? "nod" : "wave_right","camera_mode"=>"character"}
      end
      def self.catalog(access:,scene_id:)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        performer=scene.scene_objects.find { |object| object.definition["character_profile"] }
        actor=performer && StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready").find_by(id:performer.definition["asset_id"])
        current_defaults=defaults(scene.settings.dig("production_brief","template_key").to_s)
        current_defaults["name"]=actor.name if actor
        current={key:"current",name:"Current scene set",description:"Use this scene's editable sets, lights and cameras in a separate short. Replace its blocking cast with the chosen performer.",defaults:current_defaults.merge("cast_asset_id"=>actor&.id),available:!scene.blender_source.attached? && !scene.settings["native_blender_asset_id"]}
        scene_rows=[{key:"studio",name:"Plain character stage",description:"A clean stage for checking performance and speech.",defaults:defaults("studio"),available:true},current]+recipes.map { |row| {key:"library:#{row['key']}",name:row["name"],description:row["description"],defaults:defaults(row["key"]),available:true} }
        scene_rows.insert(1,{key:"control_panel",name:"Control-panel interaction",description:"An editable panel and activation button with reachable face-center targets.",defaults:defaults("studio").merge("dialogue"=>"Panel activated.","gesture"=>"still"),available:true})
        scene_rows.insert(2,{key:"bench",name:"Walk, sit and stand",description:"A calibrated eight-second bench performance with planted feet and seat support.",defaults:defaults("studio").merge("dialogue"=>"We can build this world together.","gesture"=>"still","mechanics"=>{"action"=>"bench","version"=>2,"target_id"=>"seat"}),available:true})
        scene_rows.insert(3,{key:"carry",name:"Pick up, carry and put down",description:"A calibrated parcel grip, walk and release onto a second table.",defaults:defaults("studio").merge("dialogue"=>"I have got it. Let us move.","gesture"=>"still","mechanics"=>{"action"=>"carry","version"=>1,"target_id"=>"parcel"}),available:true})
        scene_rows.insert(4,{key:"grasp",name:"Physical finger grasp",description:"Torque-limited fingers close around a free sphere, lift it through friction and release it onto a table. The character faces the table and looks down at the sphere before reaching.",defaults:defaults("studio").merge("dialogue"=>"A real grip.","gesture"=>"still","camera_mode"=>"template","mechanics"=>{"action"=>"grasp","version"=>2,"target_id"=>"ball"}),available:true})
        scene_rows.insert(5,{key:"grasp_acting",name:"Pedestal pickup · acting beats",description:"Gaze leads the reach, a weight check marks lift-off, breathing and grip adjustments sustain the hold, then placement and follow-through.",defaults:defaults("studio").merge("dialogue"=>"There we go.","gesture"=>"still","camera_mode"=>"template","mechanics"=>{"action"=>"grasp","version"=>3,"target_id"=>"ball"}),available:true})
        scene_rows.insert(6,{key:VerifiedGrasp::KEY,name:"Pick up, inspect and return",description:"Validated eight-second contact action with a reusable weighted hand. Requires a contact_biped v1 character and the calibrated ball.",defaults:defaults("studio").merge("dialogue"=>"","gesture"=>"still","camera_mode"=>"template","mechanics"=>{"action"=>"grasp","version"=>4,"target_id"=>"ball"}),required_profile:"contact_biped",available:true})
        scene_rows << {key:HANDOFF_KEY,name:"Pass a parcel across the counter",description:"The first character slides a parcel into reach, both hands briefly share it, and the second character slides it the rest of the way. The counter supports the prop throughout.",defaults:defaults("studio"),available:true,dialogue_only:true}
        scene_rows.each do |row|
          objects=case row[:key]
          when "studio" then []
          when HANDOFF_KEY then []
          when "control_panel" then control_panel
          when "bench" then bench
          when "carry" then Carry.objects
          when "grasp" then Grasp.objects
          when VerifiedGrasp::KEY then VerifiedGrasp.objects
          when "grasp_acting" then Grasp.acting_objects
          when "current" then scene.scene_objects.map { |object| {"id"=>object.id,"name"=>object.name,"type"=>object.object_type,"definition"=>object.definition} }
          else Studio::Library::Catalog.objects(row[:key].delete_prefix("library:")).each_with_index.map { |object,i| object.merge("id"=>i+1) }
          end
          row[:contact_targets]=Contact.targets(objects)
          row[:mechanics_targets]=objects.select { |obj| obj.dig("definition","mechanics_seat")==1 || obj.dig("definition","mechanics_carry")==1 || obj.dig("definition","mechanics_grasp")==1 }.map { |obj| {id:obj["id"].to_s,name:obj["name"],action:obj.dig("definition","mechanics_grasp")==1 ? "grasp" : obj.dig("definition","mechanics_carry")==1 ? "carry" : "bench",version:obj.dig("definition","mechanics_grasp_version") || (obj.dig("definition","mechanics_seat")==1 || obj.dig("definition","mechanics_grasp")==1 ? 2 : 1)} }
        end
        production_rows=Studio::NativeBlender::MediaPresets.items.select { |row| row["project_template"] && !row["requires_asset"] }.map { |row| row.slice("key","name","category","scene_count","description") }
        saved=access.projects.where(site_id:access.site_id,is_template:true).order(:name,:id).limit(100).map { |project| {id:project.id,name:project.name,scene_count:project.studio_scenes.count} }
        {scene_templates:scene_rows,production_templates:production_rows,saved_templates:saved,default_scene_template:current[:available] && scene.scene_objects.exists? ? "current" : "studio"}
      end
      def self.launch(access:,payload:)
        source=access.scene!(payload.fetch("scene_id"));raise ActiveRecord::RecordNotFound unless source.studio_project.site_id==access.site_id
        key=payload.fetch("request_key").to_s;name=payload.fetch("name").to_s.strip;kind=payload.fetch("source").to_s
        raise ArgumentError,"Name the new production (1–120 characters)" unless name.length.between?(1,120)
        raise ArgumentError,"Use a valid template request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        inputs={"source"=>kind,"name"=>name}
        if kind=="production"
          token=payload.fetch("template_key").to_s
          record=Studio::NativeBlender::MediaPresets.items.find { |row| row["key"]==token && row["project_template"] && !row["requires_asset"] }
          raise ArgumentError,"Choose an available production template" unless record
          inputs["template_key"]=token
        elsif kind=="saved"
          template=access.projects.where(site_id:access.site_id,is_template:true).find(payload.fetch("project_id"))
          inputs["project_id"]=template.id
        else
          raise ArgumentError,"Choose a production template or saved show"
        end
        operation=access.user.with_lock do
          scope=StudioOperation.where(capability:LAUNCH_CAPABILITY,studio_project_id:access.projects.where(site_id:access.site_id).select(:id)).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'request_key' = ?",key).first
          if previous
            raise ArgumentError,"This template key belongs to different inputs" unless previous.manifest["inputs"]==inputs && previous.studio_scene_id==source.id
            next previous
          end
          raise ArgumentError,"Wait before creating another template production" if scope.where("created_at > ?",1.minute.ago).count>=3
          result=if kind=="production"
            Studio::NativeBlender::PresetUse.call(access:access,payload:{"key"=>inputs["template_key"],"mode"=>"new_project","name"=>name,"request_key"=>"template-launch-#{Digest::SHA256.hexdigest(key).first(48)}"})
          else
            Studio::Workers::Workspace.perform("template_use",{"user_id"=>access.user.id,"site_id"=>access.site_id,"project_id"=>template.id,"name"=>name,"request_key"=>"template-launch-#{Digest::SHA256.hexdigest(key).first(48)}"})
          end
          project=access.projects.where(site_id:access.site_id).find(result.fetch(:project_id))
          receipt={"project_id"=>project.id,"name"=>project.name,"scenes"=>project.studio_scenes.order(:id).map { |scene| {"id"=>scene.id,"name"=>scene.name} },"status"=>"staged"}
          source.studio_operations.create!(studio_project:source.studio_project,production:source.production,operation_type:"template_launch",provider:"studio",capability:LAUNCH_CAPABILITY,status:"completed",completed_at:Time.current,intent:{"user_id"=>access.user.id},manifest:{"inputs"=>inputs},metadata:{"request_key"=>key,"result"=>receipt})
        end
        operation.metadata.fetch("result")
      end
      def self.snapshot(access:,source:,key:,performer_count:1)
        return {"key"=>"studio","name"=>"Plain character stage","settings"=>{},"objects"=>[],"assets"=>[]} if key=="studio"
        if key==HANDOFF_KEY
          raise ArgumentError,"The counter handoff needs two performers" unless performer_count==2
          return {"key"=>key,"name"=>"Pass a parcel across the counter","settings"=>{},"objects"=>counter_handoff,"assets"=>[]}
        end
        if key==VerifiedGrasp::KEY
          objects=VerifiedGrasp.objects;settings={"fps"=>24,"camera_cuts"=>[{"camera_id"=>"grasp_wide","frame"=>1},{"camera_id"=>"grasp_close","frame"=>79},{"camera_id"=>"grasp_recovery","frame"=>145}]};name="Pick up, inspect and return"
        elsif key=="grasp_acting"
          objects=Grasp.acting_objects;settings={"fps"=>12,"camera_cuts"=>[{"camera_id"=>"grasp_wide","frame"=>1},{"camera_id"=>"grasp_close","frame"=>16},{"camera_id"=>"grasp_medium","frame"=>37},{"camera_id"=>"grasp_close","frame"=>55},{"camera_id"=>"grasp_wide","frame"=>75}]};name="Pedestal pickup · acting beats"
        elsif key=="grasp"
          objects=Grasp.objects;settings={"fps"=>12,"camera_cuts"=>[{"camera_id"=>"grasp_wide","frame"=>1},{"camera_id"=>"grasp_close","frame"=>13},{"camera_id"=>"grasp_wide","frame"=>85}]};name="Physical finger grasp"
        elsif key=="carry"
          objects=Carry.objects;settings={};name="Pick up, carry and put down"
        elsif key=="bench"
          objects=bench;settings={};name="Walk, sit and stand"
        elsif key=="control_panel"
          objects=control_panel
          objects.each { |object| object["definition"]["location"][0]-=1.0 } if performer_count==2
          settings={};name="Control-panel interaction"
        elsif key=="current"
          raise ArgumentError,"Open packed native source scenes in the advanced editor; choose an editable scene setup for this short" if source.blender_source.attached? || source.settings["native_blender_asset_id"]
          settings=source.settings.deep_dup
          objects=source.scene_objects.map { |object| {"id"=>object.id,"name"=>object.name,"type"=>object.object_type,"definition"=>object.definition.deep_dup} }
          name=source.name
        else
          recipe=recipes.find { |row| "library:#{row['key']}"==key }
          raise ArgumentError,"Choose an available scene template" unless recipe
          objects=Studio::Library::Catalog.objects(recipe["key"]).each_with_index.map { |object,index| object.deep_dup.merge("id"=>index+1) }
          settings={};name=recipe["name"]
        end
        actor=objects.find { |object| object.dig("definition","character_profile") }
        placeholder=objects.find { |object| object.dig("definition","body_part")=="torso" }
        transform=actor && actor["definition"].slice("location","rotation","scale")
        unless transform
          position=placeholder&.dig("definition","location") || [0,0,0]
          floors=objects.select do |object|
            definition=object["definition"]
            object["name"].match?(/floor|deck|ground/i) && %w[cube plane].include?(object["type"]) && Array(definition.fetch("rotation",[0,0,0])).all? { |value| value.to_f%360==0 } &&
              position.first(2).zip(definition.fetch("location",[0,0,0]).first(2),definition.fetch("scale",[1,1,1]).first(2)).all? { |point,center,extent| (point-center).abs<=extent.abs }
          end
          height=floors.map { |object| object["definition"].fetch("location",[0,0,0])[2]+(object["type"]=="cube" ? object["definition"].fetch("scale",[1,1,1])[2].abs : 0) }.max
          transform={"location"=>[position[0],position[1],height ? height+0.04 : 0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}
        end
        if transform
          transform.each_value do |vector|
            raise ArgumentError,"Template performer transforms must be finite three-dimensional values" unless vector.is_a?(Array) && vector.size==3 && vector.all? { |value| value.is_a?(Numeric) && value.finite? && value.abs<=1000 }
          end
        end
        motion=actor && actor["definition"].slice("asset_id","character_profile","motion_clips")
        # Reusable cast is supplied explicitly; blocking mannequins are not performers.
        objects.reject! { |object| object.dig("definition","character_profile") || object.dig("definition","character_key") || object.dig("definition","blocking_actor") || object.dig("definition","director_speaker") }
        raise ArgumentError,"Choose a setup with at most 64 set, light and camera objects" if objects.length>64
        assets=objects.select { |object| object["type"]=="imported_asset" }.map do |object|
          asset=StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready",kind:%w[blend glb]).find(object.fetch("definition").fetch("asset_id"))
          attachment=asset.kind=="blend" && asset.native.attached? ? asset.native : asset.proxy
          raise ArgumentError,"Prepare the template model source before using it" unless attachment.attached?
          blob=attachment.blob
          {"id"=>asset.id,"blob_id"=>blob.id,"native"=>asset.kind=="blend" && asset.native.attached?}
        end.uniq
        result={"key"=>key,"name"=>name,"settings"=>settings.except("library_requests","json_preset_requests","cast_receipts","performance_receipts","motion_receipts","look_receipts","shot_board","shot_board_receipts","workspace","timeline","music","authoring_history","authoring_redo","character_scene_cameras","dialogue_scene_cameras","dialogue_timing"),"objects"=>objects,"assets"=>assets}
        result["actor_transform"]=transform if transform.present?
        result["actor_motion"]=motion if motion && motion["motion_clips"]
        raise ArgumentError,"This scene setup is too large for a performed-short snapshot" if JSON.generate(result).bytesize>256.kilobytes
        result
      end
      def self.apply!(scene,staging,access:)
        copies={}
        staging.fetch("assets").each do |reference|
          asset=StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready").find(reference.fetch("id"))
          blob=reference["native"] ? asset.native.blob : asset.proxy.blob
          raise ArgumentError,"A template asset changed after preparation. Start a new short using its current version." unless blob.id==reference["blob_id"]
          copy=StudioAsset.new(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,name:asset.name+" · scene copy",kind:asset.kind,status:"ready",request_key:"scene-template-#{scene.id}-asset-#{asset.id}",metadata:asset.metadata.merge("template_source_asset_id"=>asset.id))
          %i[file native proxy thumbnail bundle].each { |name| copy.public_send(name).attach(asset.public_send(name).blob) if asset.public_send(name).attached? }
          copy.save!;copies[asset.id]=copy.id
        end
        map={}
        staging.fetch("objects").each_with_index do |object,index|
          definition=object.fetch("definition").deep_dup.merge("template_source_object_id"=>object.fetch("id").to_s)
          definition["asset_id"]=copies.fetch(definition["asset_id"]) if object["type"]=="imported_asset"
          child=scene.scene_objects.create!(name:object.fetch("name"),object_type:object.fetch("type"),position:index,definition:definition)
          map[object.fetch("id")]=child.id
        end
        settings=staging.fetch("settings").deep_dup
        settings["active_camera_object_id"]=map[settings["active_camera_object_id"]] if settings["active_camera_object_id"]
        fps=Float(settings.fetch("fps",24))/Float(settings.fetch("fps_base",1))
        raise ArgumentError,"Use a finite template frame rate from 1–120 fps" unless fps.finite? && fps.between?(1,120)
        authored=Array(settings["camera_cuts"]).deep_dup
        Array(settings["blender_presets"]).each do |preset|
          Array(preset["camera_cuts"]).each do |cut|
            source=staging["objects"].find { |object| object["type"]=="camera" && object.dig("definition","preset_instance")==preset["instance"] && (object.dig("definition","production_shot_name") || object["name"])==cut["camera"] }
            authored<<{"camera_id"=>source["id"],"frame"=>cut["frame"]} if source
          end
          preset["camera_cuts"]=[]
        end
        limit = staging.fetch("script_frame_end", staging["key"]==VerifiedGrasp::KEY ? 192 : %w[grasp grasp_acting].include?(staging["key"]) ? 96 : 36)
        settings["camera_cuts"]=authored.filter_map do |cut|
          target_fps=staging["key"]==VerifiedGrasp::KEY ? 24 : 12
          frame=1+((cut.fetch("frame")-1)*target_fps/fps).round
          {"camera_id"=>map.fetch(cut.fetch("camera_id")),"frame"=>frame} if frame.between?(1,limit)
        end.uniq { |cut| cut["frame"] }.sort_by { |cut| cut["frame"] }
        scene.update!(settings:settings.merge(scene.settings).merge("template_source"=>staging.slice("key","name")))
      end
    end
  end
end
