# frozen_string_literal: true
module Studio
  module Spatial
    class Publication
      SETTINGS=%w[fps fps_base frame_start frame_end frame_current render_engine resolution_x resolution_y active_camera active_camera_object_id native_blender_asset_id native_scene native_preserve native_bundle_path world_color source_credits].freeze
      def self.validate_scope!(publication,community_id)
        community=Community.find_by(id:community_id)
        if community && community.visibility!="public" && publication.metadata["community_slug"]!=community.slug
          raise ArgumentError,"This remix contains private-community assets; publish it back to #{community.name}"
        end
      end
      def self.capture!(publication,access:,scene:,remix:false,rights_confirmed:false)
        raise ArgumentError,"Confirm permission to share the scene and its assets" unless rights_confirmed
        raise ArgumentError,"Spatial posts need a Lightek social destination" unless publication.platform=="lightek_social"
        source_community=scene.settings["remix_source_community_id"]
        validate_scope!(publication,source_community) if source_community
        snapshot=Blender::ManifestBuilder.new(scene).call
        snapshot["scene"]["settings"]=snapshot["scene"]["settings"].slice(*SETTINGS)
        raise ArgumentError,"Use at most 2000 scene elements in a spatial post" if snapshot["scene"]["objects"].size>2000
        snapshot["scene"]["objects"].each { |object| object["definition"]=object["definition"].except("asset_path","credential_ref") }
        snapshot["revision"]=scene.lock_version
        ids=snapshot["scene"]["objects"].filter_map { |object| object.dig("definition","asset_id") }.uniq
        ids<<scene.settings["native_blender_asset_id"] if scene.settings["native_blender_asset_id"]
        raise ArgumentError,"Use at most 16 spatial asset files per post" if ids.uniq.size>16
        assets=StudioAsset.for_actor(access).where(id:ids.uniq,status:"ready")
        raise ArgumentError,"Prepare all scene assets before spatial publishing" unless assets.count==ids.uniq.size
        refs=assets.map do |asset|
          validate_scope!(publication,asset.metadata["remix_source_community_id"]) if asset.metadata["remix_source_community_id"]
          license=asset.metadata.dig("source","license").to_s
          if remix && license.match?(/BY[- ]SA|share.?alike/i)
            raise ArgumentError,"#{asset.name}: preserve its share-alike license before enabling this CC-BY remix grant"
          end
          if remix && license.present? && !license.match?(/\ACC0|\ACC[- ]BY(?:\s|[- ]4|\z)|creative commons attribution|public domain/i)
            raise ArgumentError,"#{asset.name}: its license does not grant automatic remix sharing"
          end
          raise ArgumentError,"#{asset.name} needs a browser proxy" unless asset.proxy.attached?
          publication.spatial_files.attach(asset.proxy.blob)
          proxy=publication.spatial_files.attachments.find_by!(blob_id:asset.proxy.blob.id)
          source=asset.kind=="blend" && asset.native.attached? ? asset.native : asset.file
          source_id=nil;bundle_id=nil
          if remix
            publication.spatial_files.attach(source.blob);source_id=source.blob.id
            if asset.bundle.attached?;publication.spatial_files.attach(asset.bundle.blob);bundle_id=asset.bundle.blob.id;end
          end
          {"id"=>asset.id,"name"=>asset.name,"kind"=>asset.kind,"proxy_blob_id"=>proxy.blob_id,"source_blob_id"=>source_id,"bundle_blob_id"=>bundle_id,"metadata"=>asset.metadata.slice("source","source_credits","source_scene","native_blender","native_inventory_version","scenes")}
        end
        publication.spatial_scene.attach(io:StringIO.new(snapshot.to_json),filename:"scene-#{scene.id}-#{scene.lock_version}.json",content_type:"application/json")
        publication.update!(metadata:publication.metadata.merge("sources"=>(Array(publication.metadata["sources"])+Array(snapshot["credits"])).uniq,"spatial"=>{"version"=>1,"allow_remix"=>remix,"license"=>remix ? "CC-BY-4.0" : "view-only","assets"=>refs,"creator_id"=>access.user.id,"scene_id"=>scene.id,"scene_revision"=>scene.lock_version}))
      end
      def self.attach!(publication,post)
        return unless publication.spatial_scene.attached?
        post.spatial_scene.attach(publication.spatial_scene.blob)
        publication.spatial_files.each { |file| post.spatial_files.attach(file.blob) }
        post.update!(metadata:post.metadata.merge("spatial"=>publication.metadata.fetch("spatial")))
      end
      def self.snapshot(post)
        raise ActiveRecord::RecordNotFound unless post.spatial_scene.attached?
        JSON.parse(post.spatial_scene.download)
      end
      def self.manifest(post)
        scene=snapshot(post).fetch("scene")
        refs=post.metadata.fetch("spatial").fetch("assets").index_by { |ref| ref["id"].to_i }
        objects=scene.fetch("objects").map do |object|
          definition=object.fetch("definition").deep_dup
          if definition["asset_id"]
            ref=refs.fetch(definition["asset_id"].to_i)
            definition["asset_proxy_url"]="/api/lightek/pwa/posts/#{post.id}/spatial/assets/#{ref.fetch('id')}"
          end
          {"id"=>object["id"],"name"=>object["name"],"object_type"=>object["type"],"definition"=>definition}
        end
        {version:1,coordinate_space:"Y_UP_METERS",post_id:post.id,scene:{id:scene["id"],coordinate_space:"BLENDER_Z_UP_METERS",objects:objects,settings:scene["settings"]},assets:[],window_width_m:0.5,remix:post.metadata["spatial"].slice("allow_remix","license","creator_id"),sources:post.metadata["sources"]}
      end
      def self.import_asset!(post,access:,asset_id:,request_key:)
        raise ArgumentError,"The creator has not permitted asset reuse" unless post.metadata.dig("spatial","allow_remix")
        raise ArgumentError,"Invalid asset import request" unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        ref=post.metadata.fetch("spatial").fetch("assets").find { |entry| entry["id"].to_i==asset_id.to_i } or raise ActiveRecord::RecordNotFound
        access.user.with_lock do
          existing=StudioAsset.find_by(owner_id:access.user.id,request_key:request_key)
          if existing
            raise ArgumentError,"Import key already used" unless existing.site_id==access.site_id && existing.metadata["remix_source_post_id"]==post.id && existing.metadata["remix_source_asset_id"]==ref["id"]
            return existing
          end
          asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,name:ref["name"],kind:ref["kind"],status:"ready",request_key:request_key,
            metadata:ref.fetch("metadata",{}).merge("remix_source_post_id"=>post.id,"remix_source_community_id"=>post.community_id,"remix_source_asset_id"=>ref["id"],"source"=>{"name"=>ref["name"],"author"=>post.user.profile.public_display_name,"license"=>post.metadata.dig("spatial","license"),"source_post_id"=>post.id},"source_credits"=>Array(ref.dig("metadata","source_credits"))+[ref.dig("metadata","source")].compact))
          source=post.spatial_files.blobs.find(ref.fetch("source_blob_id"));asset.file.attach(source);asset.proxy.attach(post.spatial_files.blobs.find(ref.fetch("proxy_blob_id")))
          asset.native.attach(source) if ref["kind"]=="blend"
          asset.bundle.attach(post.spatial_files.blobs.find(ref["bundle_blob_id"])) if ref["bundle_blob_id"]
          asset
        end
      end
      def self.fork!(post,access:,request_key:)
        raise ArgumentError,"The creator has not enabled scene remixing" unless post.metadata.dig("spatial","allow_remix")
        raise ArgumentError,"A remix request key is required" unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        access.user.with_lock do
          existing=access.projects.find_by(owner_id:access.user.id,request_key:request_key)
          if existing
            raise ArgumentError,"Request key already used" unless existing.studio_scenes.first&.settings&.dig("remix_source_post_id")==post.id
            return {project_id:existing.id,scene_id:existing.studio_scenes.first.id}
          end
          original=snapshot(post).fetch("scene");project=StudioProject.create!(owner:access.user,site_id:access.site_id,name:"Remix · #{post.title}".first(160),request_key:request_key)
          project.studio_scenes.destroy_all;mapping={}
          post.metadata.fetch("spatial").fetch("assets").each do |ref|
            proxy=post.spatial_files.blobs.find(ref.fetch("proxy_blob_id"));source=post.spatial_files.blobs.find(ref.fetch("source_blob_id"))
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,studio_project:project,name:ref["name"],kind:ref["kind"],status:"ready",request_key:"#{request_key}-#{ref['id']}",metadata:ref.fetch("metadata",{}).merge("remix_source_post_id"=>post.id,"remix_source_community_id"=>post.community_id))
            asset.file.attach(source);asset.proxy.attach(proxy);asset.native.attach(source) if ref["kind"]=="blend"
            asset.bundle.attach(post.spatial_files.blobs.find(ref["bundle_blob_id"])) if ref["bundle_blob_id"]
            mapping[ref["id"].to_i]=asset
          end
          settings=original.fetch("settings").merge("remix_source_post_id"=>post.id,"remix_source_community_id"=>post.community_id,"remix_creator_id"=>post.user_id,"source_credits"=>Array(original.dig("settings","source_credits"))+[{"name"=>post.title,"author"=>post.user.profile.public_display_name,"license"=>post.metadata.dig("spatial","license"),"source_post_id"=>post.id}])
          settings["native_blender_asset_id"]=mapping.fetch(settings["native_blender_asset_id"].to_i).id if settings["native_blender_asset_id"]
          scene=project.studio_scenes.create!(name:original["name"],settings:settings)
          id_map={}
          original.fetch("objects").each do |item|
            definition=item.fetch("definition").deep_dup
            if definition["asset_id"];asset=mapping.fetch(definition["asset_id"].to_i);definition.merge!("asset_id"=>asset.id,"asset_proxy_url"=>"/api/lightek/pwa/assets/#{asset.id}/proxy");end
            object=scene.scene_objects.create!(name:item["name"],object_type:item["type"],definition:definition)
            id_map[item["id"].to_i]=object.id
          end
          scene.settings["active_camera_object_id"]=id_map[settings["active_camera_object_id"].to_i] if settings["active_camera_object_id"]
          if (native=mapping.values.find { |asset| asset.id==scene.settings["native_blender_asset_id"] })
            scene.blender_source.attach(native.native.blob);scene.blender_bundle.attach(native.bundle.blob) if native.bundle.attached?
          end
          scene.save!;{project_id:project.id,scene_id:scene.id,source_post_id:post.id}
        end
      end
    end
  end
end
