# frozen_string_literal: true
module Studio
  module Performance
    class Cast
      CONTROLS=%w[jaw_open smile blink brow_raise mouth_wide mouth_round].freeze
      GESTURES=%w[head left_arm right_arm].freeze
      def self.inventory(asset)
        asset.metadata.slice("character_profile","performer_build","duration","has_audio","source_scene","missing_dependencies").merge("scenes"=>Array(asset.metadata["scenes"]).map do |scene|
          {"name"=>scene["name"],"objects"=>Array(scene["objects"]).map do |object|
            {"name"=>object["name"],"definition"=>object.fetch("definition",{}).slice("native_type","shape_keys").merge("bones"=>Array(object.dig("definition","bones")).map { |bone| bone.slice("name") })}
          end}
        end)
      end

      def self.profile(asset, raw)
        raw=raw.to_h.deep_stringify_keys
        source=Array(asset.metadata["scenes"]).find{|s|s["name"]==raw.fetch("source_scene")}
        raise ArgumentError,"Choose a scene from a prepared, packed Blender character" unless asset.kind=="blend" && asset.status=="ready" && asset.native.attached? && source && Array(asset.metadata["missing_dependencies"]).empty?
        raise ArgumentError,"Pack this character into a standalone .blend before adding it to Cast" if asset.bundle.attached?
        objects=Array(source["objects"]).select{|o|%w[MESH ARMATURE EMPTY CURVE FONT].include?(o.dig("definition","native_type"))}
        raise ArgumentError,"Use a character with 1–256 objects" unless objects.length.between?(1,256)
        bindings=raw.fetch("bindings").to_h.slice(*CONTROLS).transform_values do |binding|
          binding=binding.to_h.slice("object","key")
          object=objects.find{|o|o["name"]==binding["object"]}
          raise ArgumentError,"Choose an available facial shape key" unless object && Array(object.dig("definition","shape_keys")).any?{|key|key["name"]==binding["key"] && key["name"]!="Basis"}
          binding
        end
        raise ArgumentError,"Bind a jaw-open shape key before saving a speaking character" unless bindings["jaw_open"]
        raise ArgumentError,"Each face control needs its own shape key" unless bindings.values.uniq.length==bindings.length
        bones=raw.fetch("bones",{}).to_h.slice(*GESTURES).transform_values do |binding|
          binding=binding.to_h.slice("object","bone")
          object=objects.find{|o|o["name"]==binding["object"]}
          raise ArgumentError,"Choose an available character bone" unless object && Array(object.dig("definition","bones")).any?{|bone|bone["name"]==binding["bone"]}
          binding
        end
        raise ArgumentError,"Each gesture needs its own bone" unless bones.values.uniq.length==bones.length
        {"version"=>1,"source_scene"=>source["name"],"source_blob_id"=>asset.native.blob.id,"objects"=>objects.map{|o|o["name"]},"bindings"=>bindings,"bones"=>bones}
      end

      def self.register(access:,payload:)
        source=StudioAsset.for_actor(access).find(payload.fetch("asset_id"))
        values=profile(source,payload.fetch("profile"))
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A cast request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        actor=nil
        access.user.with_lock do
          actor=StudioAsset.find_by(owner:access.user,request_key:key)
          if actor
            raise ArgumentError,"This request key belongs to another character" unless actor.site_id==access.site_id && actor.metadata["cast_source_asset_id"]==source.id
          else
            actor=StudioAsset.new(owner:access.user,site_id:access.site_id,name:payload.fetch("name",source.name).to_s.first(160),kind:"blend",status:"ready",request_key:key,
              metadata:source.metadata.merge("character_profile"=>values,"cast_source_asset_id"=>source.id))
            actor.file.attach(source.native.blob);actor.native.attach(source.native.blob)
            actor.proxy.attach(source.proxy.blob) if source.proxy.attached?
            actor.thumbnail.attach(source.thumbnail.blob) if source.thumbnail.attached?
            actor.save!
          end
        end
        {asset_id:actor.id,name:actor.name}
      end

      def self.create(access:,payload:)
        values=%w[skin wardrobe hair].to_h do |field|
          value=payload.fetch(field,{"skin"=>"#925e43","wardrobe"=>"#64388b","hair"=>"#211916"}[field]).to_s
          raise ArgumentError,"Choose six-digit colors" unless value.match?(/\A#[0-9a-fA-F]{6}\z/)
          [field,value]
        end
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A performer request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        asset=nil
        access.user.with_lock do
          asset=StudioAsset.find_by(owner:access.user,request_key:key)
          if asset
            raise ArgumentError,"This request key belongs to another build" unless asset.site_id==access.site_id && asset.metadata["performer_build"]==values
          else
            pending=StudioAsset.where(owner:access.user,status:"processing").where("metadata ->> 'performer_build' IS NOT NULL").count
            raise ArgumentError,"Wait for your current performer builds to finish" if pending>=4
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,name:payload.fetch("name","Lightek performer").to_s.first(160),kind:"blend",status:"processing",request_key:key,metadata:{"performer_build"=>values})
            StudioCharacterCreateJob.perform_later(asset.id)
          end
        end
        {asset_id:asset.id,status:asset.status}
      end

      def self.retry(access:,payload:)
        asset=StudioAsset.for_actor(access).find(payload.fetch("asset_id"))
        asset.with_lock do
          raise ArgumentError,"Only failed Lightek performer builds can be retried" unless asset.status=="failed" && asset.metadata["performer_build"]
          asset.update!(status:"processing",error_message:nil)
          StudioCharacterCreateJob.perform_later(asset.id)
        end
        {asset_id:asset.id,status:asset.status}
      end

      def self.place(access:,payload:)
        actor=StudioAsset.for_actor(access).where(status:"ready",kind:"blend").find(payload.fetch("asset_id"))
        profile=actor.metadata["character_profile"] || raise(ArgumentError,"Save the asset to Cast first")
        scene=access.scene!(payload.fetch("scene_id"));key=payload.fetch("request_key").to_s
        raise ArgumentError,"A placement request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        result=nil
        scene.with_lock do
          receipts=scene.settings.fetch("cast_receipts",{})
          if receipts[key]
            raise ArgumentError,"This placement key belongs to another character" unless receipts[key]["asset_id"]==actor.id
            return receipts[key]
          end
          scene.lock_version=Integer(payload.fetch("lock_version"))
          raise ArgumentError,"Use at most sixteen Cast members in one scene" if scene.scene_objects.count { |item| item.definition["character_profile"] }>=16
          object=scene.scene_objects.create!(name:actor.name,object_type:"imported_asset",position:scene.scene_objects.maximum(:position).to_i+1,
            definition:{"asset_id"=>actor.id,"asset_proxy_url"=>"/api/lightek/pwa/assets/#{actor.id}/proxy","category"=>"character","location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1],"character_profile"=>profile.deep_dup})
          unless scene.scene_objects.exists?(object_type:"camera")
            scene.scene_objects.create!(name:"Performance portrait",object_type:"camera",definition:{"location"=>[0,-5,1.8],"look_at"=>[0,0,1.4],"lens"=>55})
          end
          unless scene.scene_objects.where(object_type:%w[area_light point_light sun_light]).exists?
            Studio::Library::Catalog.lights.each { |light| scene.scene_objects.create!(name:light["name"],object_type:light["type"],definition:light["definition"]) }
          end
          result={"scene_id"=>scene.id,"object_id"=>object.id,"asset_id"=>actor.id,"lock_version"=>scene.lock_version+1}
          scene.update!(settings:scene.settings.merge("cast_receipts"=>receipts.to_a.last(99).to_h.merge(key=>result),"native_revision"=>scene.settings.fetch("native_revision",0).to_i+1))
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before placing the character."
      end
    end
  end
end
