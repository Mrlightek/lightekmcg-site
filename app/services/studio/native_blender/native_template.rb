# frozen_string_literal: true
module Studio
  module NativeBlender
    class NativeTemplate
      def self.call(access:,payload:)
        asset=StudioAsset.for_actor(access).where(kind:"blend",status:"ready").find(payload.fetch("asset_id"))
        raise ArgumentError,"Prepare this file's native Blender metadata first" unless asset.native.attached? && asset.metadata["native_blender"]
        raise ArgumentError,"Refresh this file’s Blender object metadata before creating a native project" unless asset.metadata["native_inventory_version"]==1
        missing=Array(asset.metadata["missing_dependencies"])
        raise ArgumentError,"This Blender file has missing dependencies: #{missing.first(5).join(', ')}" if missing.any?
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A template request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        selected=payload["source_scene"].presence
        sources=Array(asset.metadata["scenes"])
        sources=sources.select { |scene| scene["name"]==selected } if selected
        raise ArgumentError,"Choose an available Blender scene" if sources.empty?
        result=nil
        access.user.with_lock do
          project=StudioProject.find_by(owner_id:access.user.id,request_key:key)
          if project
            raise LightekCommunity::AccessDenied,"Template receipt belongs to another application" unless project.site_id==access.site_id
            return {project_id:project.id,scene_id:project.studio_scenes.first.id}
          end
          project=StudioProject.create!(owner:access.user,site_id:access.site_id,name:payload["name"].presence || asset.name.first(120),request_key:key,
            description:"Native Blender template · #{asset.name}")
          project.studio_scenes.destroy_all
          production=project.productions.create!(name:project.name,kind:"general",status:"development",metadata:{"native_blender_asset_id"=>asset.id,"source"=>asset.metadata["source"]})
          sources.first(100).each do |source|
            settings=source.fetch("settings",{}).merge("native_blender_asset_id"=>asset.id,"native_scene"=>source.fetch("name"),"active_camera"=>source["active_camera"],"native_preserve"=>true,"native_bundle_path"=>asset.metadata["bundle_relative_source"],"source_credits"=>[asset.metadata["source"]].compact)
            scene=project.studio_scenes.create!(production:production,name:source["name"],settings:settings)
            scene.scene_objects.create!(name:"#{asset.name} · Blender source",object_type:"imported_asset",position:0,
              definition:{"asset_id"=>asset.id,"native_source_preview"=>true,"asset_proxy_url"=>"/api/lightek/pwa/assets/#{asset.id}/proxy","location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}) if asset.proxy.attached? && source["name"]==asset.metadata["source_scene"]
            scene.blender_source.attach(asset.native.blob)
            scene.blender_bundle.attach(asset.bundle.blob) if asset.bundle.attached?
            Array(source["objects"]).first(2000).each_with_index do |item,index|
              definition=item.fetch("definition").deep_dup
              definition["native_original"]=definition.deep_dup
              scene.scene_objects.create!(name:item.fetch("name"),object_type:"native_object",position:index+129,definition:definition)
            end
            Array(source["cameras"]).first(128).each_with_index do |camera,index|
              definition=camera.fetch("definition").deep_dup
              definition["native_original"]=camera.fetch("definition").deep_dup
              scene.scene_objects.create!(name:camera["name"],object_type:"camera",position:index+1,definition:definition)
            end
          end
          result={project_id:project.id,scene_id:project.studio_scenes.first.id}
        end
        result
      end
    end
  end
end
