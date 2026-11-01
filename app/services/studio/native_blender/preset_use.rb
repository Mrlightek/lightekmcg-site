# frozen_string_literal: true
module Studio
  module NativeBlender
    class PresetUse
      def self.call(access:,payload:) = new(access,payload).call
      def initialize(access,payload) = (@access,@payload=access,payload)
      def call
        record=MediaPresets.fetch(@payload.fetch("key"));data=MediaPresets.resolve(record["key"])
        mode=@payload.fetch("mode","apply")
        raise ArgumentError,"Choose new_project, new_scenes or apply" unless %w[new_project new_scenes apply].include?(mode)
        receipt=@payload.fetch("request_key").to_s
        raise ArgumentError,"A preset request key is required" unless receipt.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        result=nil
        @access.user.with_lock do
          if mode=="new_project"
            project=StudioProject.find_by(owner_id:@access.user.id,request_key:receipt)
            if project
              raise ArgumentError,"Request key already belongs to another template" unless project.site_id==@access.site_id && project.description=="JSON Blender template: #{record['key']}"
              return {project_id:project.id,scene_id:project.studio_scenes.first.id,scene_ids:project.studio_scenes.map(&:id)}
            end
            project=StudioProject.create!(owner:@access.user,site_id:@access.site_id,name:(@payload["name"].presence || data["title"].presence || record["key"]).first(120),request_key:receipt,description:"JSON Blender template: #{record['key']}")
            project.studio_scenes.destroy_all
            production=project.productions.create!(name:project.name,kind:"general",status:"development",metadata:{"json_template_key"=>record["key"]})
            scenes=create_scenes(project,production,record,data)
            result={project_id:project.id,scene_id:scenes.first.id,scene_ids:scenes.map(&:id)}
          else
            scene=@access.scene!(@payload.fetch("scene_id"))
            scene.with_lock do
              journal=scene.settings.fetch("json_preset_requests",{})
              if journal[receipt]
                raise ArgumentError,"Request key belongs to another preset" unless journal[receipt]["key"]==record["key"] && journal[receipt]["mode"]==mode
                return journal[receipt]
              end
              scene.lock_version=Integer(@payload.fetch("lock_version"))
              scenes=mode=="new_scenes" ? create_scenes(scene.studio_project,scene.production,record,data) : [apply(scene,record)]
              result={"scene_id"=>scenes.first.id,"scene_ids"=>scenes.map(&:id),"key"=>record["key"],"mode"=>mode,"lock_version"=>scene.lock_version+1}
              scene.settings=scene.settings.merge("json_preset_requests"=>journal.to_a.last(99).to_h.merge(receipt=>result))
              scene.save!
            end
          end
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before applying a preset."
      end
      def create_scenes(project,production,record,data)
        MediaPresets.segments(data).first(100).each_with_index.map do |segment,index|
          detail=segment.is_a?(Hash) ? segment : {"name"=>segment}
          name=detail["name"] || detail["title"] || detail["slug"] || "Scene #{index+1}"
          scene=project.studio_scenes.create!(production:production,name:name.to_s.first(120),settings:StudioScene.default_settings)
          apply(scene,record)
          if detail["camera_grammar"] && MediaPresets.records.any? { |r| r["key"]==detail["camera_grammar"] }
            apply(scene,MediaPresets.fetch(detail["camera_grammar"]))
          end
          if detail["duration_seconds"]
            scene.update!(settings:scene.settings.merge("frame_start"=>1,"frame_current"=>1,"frame_end"=>(Float(detail["duration_seconds"])*scene.settings.fetch("fps",24)).round.clamp(1,216000)))
          end
          scene
        end
      end
      def apply(scene,record)
        plan=MediaPresets.compile(record["key"],title:@payload["title"])
        kind=plan["kind"];instance=SecureRandom.hex(8)
        settings=scene.settings.deep_merge(plan["settings"])
        if MediaPresets::ASSET_TYPES.include?(kind)
          raise ArgumentError,"Choose a prepared library file for this template" if @payload["asset_id"].blank?
          asset=StudioAsset.for_actor(@access).where(status:"ready").find(@payload.fetch("asset_id"))
          if %w[audio_pack audio_package].include?(kind)
            raise ArgumentError,"Choose an audio asset" unless asset.kind=="audio"
            Studio::Library::Apply.new(@access,{}).append(scene,asset)
            settings=scene.settings.deep_merge(plan["settings"])
          else
            raise ArgumentError,"Choose a packed native Blender asset" unless asset.kind=="blend" && asset.native.attached? && !asset.bundle.attached? && Array(asset.metadata["missing_dependencies"]).empty?
            plan["objects"]<<{"name"=>asset.name,"type"=>"imported_asset","definition"=>{"asset_id"=>asset.id,"location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}}
          end
        end
        if plan["directives"]["materials"] && @payload["object_id"].present?
          object=scene.scene_objects.find(@payload["object_id"])
          raise ArgumentError,"Select an editable primitive mesh" unless %w[cube sphere cylinder plane].include?(object.object_type)
          object.update!(definition:object.definition.merge("material"=>plan["directives"]["materials"].first.except("name")))
        end
        position=scene.scene_objects.maximum(:position).to_i
        plan["objects"].each_with_index do |item,index|
          object=scene.scene_objects.create!(name:item["name"].first(120),object_type:item["type"],position:position+index+1,definition:item["definition"].merge("json_preset_key"=>record["key"],"preset_instance"=>instance))
          settings.merge!("active_camera_object_id"=>object.id,"active_camera"=>object.name) if item["type"]=="camera"
        end
        directives=Array(settings["blender_presets"])
        raise ArgumentError,"Use a new scene after 100 applied JSON presets" if directives.length>=100
        directive=plan["directives"].merge("instance"=>instance,"source_sha256"=>record["source_sha256"])
        scene.update!(settings:settings.merge("blender_presets"=>directives+[directive]))
        scene
      end
    end
  end
end
