# frozen_string_literal: true
require "net/http"
module Studio
  module Spatial
    class Generation
      CONSUMER="studio_spatial_generation";PURPOSE="text_to_3d"
      def self.slug(site_id)="studio-tripo-#{site_id}"
      def self.save_provider!(site:,user:,key:)
        LightekPwa::Policy.new(user:user,site:site).authorize_admin!("studio")
        raise ArgumentError,"Enter the provider API key" unless key.to_s.length.between?(12,1024)
        LightekVault::Service.store!(name:"Studio text-to-3D · #{site.name}",slug:slug(site.id),payload:{"api_key"=>key},provider:"tripo",purpose:PURPOSE,
          access_policy:{"consumers"=>[CONSUMER],"purposes"=>[PURPOSE]},requested_by:user.email_address)
      end
      def self.submit(access:,scene_id:,prompt:,request_key:)
        scene=access.scene!(scene_id)
        raise ArgumentError,"Describe an asset in 3–2000 characters" unless prompt.to_s.length.between?(3,2000)
        raise ArgumentError,"A generation request key is required" unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        asset=nil
        access.user.with_lock do
          asset=StudioAsset.find_by(owner_id:access.user.id,request_key:request_key)
          if asset
            raise ArgumentError,"Request key already used" unless asset.site_id==access.site_id && asset.metadata.dig("generation","scene_id")==scene.id && asset.metadata.dig("generation","prompt")==prompt
          else
            # Check authorization/configuration before queuing a paid provider request.
            credential(access.site_id)
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,name:prompt.first(120),kind:"glb",status:"uploaded",request_key:request_key,
              metadata:{"generation"=>{"prompt"=>prompt,"scene_id"=>scene.id,"phase"=>"queued","provider"=>"tripo"}})
          end
        end
        StudioSpatialGenerationJob.perform_later(asset.id) if asset.metadata.dig("generation","phase")=="queued"
        asset
      end
      def self.credential(site_id)
        LightekVault::Service.checkout!(slug:slug(site_id),consumer:CONSUMER,purpose:PURPOSE,requested_by:"studio-generation")
      rescue ActiveRecord::RecordNotFound
        raise ArgumentError,"Configure Text-to-3D in Dashboard → Studio & broadcasting first"
      end
      def self.status(asset)
        generation=asset.metadata["generation"] || {}
        object=SceneObject.find_by(id:generation["object_id"],studio_scene_id:generation["scene_id"])
        {object:object && {id:object.id,name:object.name,object_type:object.object_type,definition:object.definition},asset_id:asset.id,status:asset.status,error:asset.error_message,generation:asset.metadata["generation"],thumbnail_url:asset.thumbnail.attached? ? "/api/lightek/pwa/assets/#{asset.id}/thumbnail" : nil}
      end
      def self.retry!(access,asset)
        generation=asset.metadata.fetch("generation")
        access.scene!(generation.fetch("scene_id"))
        asset.with_lock do
          raise ArgumentError,"Generation is still processing" unless asset.status=="failed" || (asset.status=="processing" && asset.updated_at<10.minutes.ago)
          raise ArgumentError,"Provider submission needs reconciliation; start a new request only after checking provider history" unless generation["task_id"] || asset.file.attached? || generation["phase"]=="configuration"
          asset.update!(status:"uploaded",error_message:nil)
        end
        StudioSpatialGenerationJob.perform_later(asset.id);asset
      end
      def self.provider(path,key,payload:nil)
        uri=URI("https://openapi.tripo3d.ai/v3/#{path}");http=Net::HTTP.new(uri.host,443,nil);http.use_ssl=true;http.open_timeout=10;http.read_timeout=30
        request=payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri);request["Authorization"]="Bearer #{key}";request["Content-Type"]="application/json";request.body=payload.to_json if payload
        response=http.request(request);data=JSON.parse(response.body)
        raise ArgumentError,"Text-to-3D provider request failed" unless response.is_a?(Net::HTTPSuccess) && data["code"]==0
        data.fetch("data")
      end
    end
  end
end
