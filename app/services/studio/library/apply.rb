# frozen_string_literal: true
module Studio
  module Library
    class Apply
      def self.call(access:, payload:)
        new(access,payload).call
      end
      def initialize(access,payload) = (@access,@payload=access,payload)
      def call
        recipe=Catalog.fetch(@payload.fetch("key"))
        scene=@access.scene!(@payload.fetch("scene_id"))
        key=@payload.fetch("request_key").to_s
        raise ArgumentError,"A library request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        result=nil
        @access.user.with_lock do
          scene.with_lock do
            journal=scene.settings.fetch("library_requests",{})
            return journal[key] if journal[key]
            scene.lock_version=Integer(@payload.fetch("lock_version"))
            ids=[];asset_ids=[]
            if recipe["target"]=="object"
              object=scene.scene_objects.find(@payload.fetch("object_id"))
              if recipe["category"]=="materials"
                raise ArgumentError,"Select a primitive mesh to apply this material" unless %w[cube sphere cylinder plane].include?(object.object_type)
                object.update!(definition:object.definition.merge("material"=>Catalog.material(recipe["key"])))
                ids<<object.id
              else
                group=object.definition["library_instance"]
                targets=group && object.definition["category"]=="characters" ? scene.scene_objects.select { |item| item.definition["library_instance"]==group && item.definition["category"]=="characters" } : [object]
                targets.each { |item| animate(item);ids<<item.id }
              end
            else
              instance=SecureRandom.hex(8)
              position=scene.scene_objects.maximum(:position).to_i
              Catalog.objects(recipe["key"]).each_with_index do |item,index|
                definition={"location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}.merge(item["definition"])
                category=item["definition"]["body_part"] ? "characters" : recipe["category"]
                object=scene.scene_objects.create!(name:item["name"],object_type:item["type"],position:position+index+1,
                  definition:definition.merge("library_key"=>recipe["key"],"library_instance"=>definition["character_key"] ? "#{instance}-#{definition['character_key']}" : instance,"category"=>category))
                ids<<object.id
              end
              generate=[]
              generate<<"audio_neural_pulse" if %w[audio_neural_pulse col_void_echo_pilot col_broadcast].include?(recipe["key"])
              generate<<"gfx_lower_thirds" if %w[gfx_lower_thirds tpl_live_interview col_broadcast].include?(recipe["key"])
              generate.each do |generated_key|
                asset=GeneratedAsset.call(access:@access,key:generated_key,title:@payload.fetch("title","LIGHTEK LIVE"),subtitle:@payload.fetch("subtitle","GUEST NAME"))
                asset_ids<<asset.id
                append(scene,asset)
              end
            end
            result={"scene_id"=>scene.id,"object_ids"=>ids,"asset_ids"=>asset_ids,"lock_version"=>scene.lock_version+1}
            scene.settings=scene.settings.merge("library_requests"=>journal.to_a.last(99).to_h.merge(key=>result))
            scene.save!
          end
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before using a library item."
      end
      def append(scene,asset)
        raw=scene.settings.fetch("timeline",{"output"=>"video","width"=>1280,"height"=>720,"clips"=>[]}).deep_dup
        raw["clips"]<<{"asset_id"=>asset.id,"in"=>0,"out"=>4,"start"=>0,"track"=>raw["clips"].length,"gain"=>asset.kind=="audio" ? 0.3 : 1}
        assets=StudioAsset.for_actor(@access).where(id:raw["clips"].map { |clip| clip["asset_id"] }).index_by(&:id)
        scene.settings=scene.settings.merge("timeline"=>Studio::Editing::Timeline.normalize(raw,assets:assets))
      end
      def animate(object)
        d=object.definition;loc=d.fetch("location",[0,0,0]);rotation=d.fetch("rotation",[0,0,0]);part=d["body_part"].to_s
        swing=part.include?("left") ? 25 : part.include?("right") ? -25 : 0
        frames=[1,13,25,37,49].each_with_index.map do |frame,index|
          phase=index%2==0 ? 1 : -1
          {"frame"=>frame,"location"=>[loc[0],loc[1]+(index==4 ? 0 : index*0.12),loc[2]+(swing==0 && index.odd? ? 0.06 : 0)],
            "rotation"=>[rotation[0]+swing*phase,rotation[1],rotation[2]]}
        end
        object.update!(definition:d.merge("animation"=>{"fps"=>24,"frames"=>frames}))
      end
    end
  end
end
