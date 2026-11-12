# frozen_string_literal: true
module Studio
  module NativeBlender
    class StarterCast
      KEYS=%w[rain_v3 snow_v4].freeze
      def self.start(access:,payload:)
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A starter scene request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        name=payload.fetch("name","My first character scene").to_s.strip
        raise ArgumentError,"Name your scene (up to 120 characters)" unless name.length.between?(1,120)
        asset=nil
        access.user.with_lock do
          asset=StudioAsset.find_by(owner:access.user,request_key:key)
          if asset
            raise ArgumentError,"This request belongs to another starter scene" unless asset.site_id==access.site_id && asset.metadata.dig("starter_cast","name")==name
          else
            raise ArgumentError,"Wait for your current starter scene to finish" if StudioAsset.where(owner:access.user,status:%w[uploaded processing]).where("metadata ->> 'starter_cast' IS NOT NULL").exists?
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,name:name,kind:"blend",status:"uploaded",request_key:key,metadata:{"starter_cast"=>{"name"=>name,"phase"=>"queued"},"source"=>{"name"=>"Rain and Snow starter cast","credits"=>KEYS.map{|id|DemoCatalog.fetch(id).slice("name","credit","license","license_url","source_page")}}})
            StudioStarterCastJob.perform_later(asset.id)
          end
          if asset.status=="failed"
            asset.update!(status:"uploaded",error_message:nil,metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"queued")))
            StudioStarterCastJob.perform_later(asset.id)
          end
        end
        receipt(asset)
      end
      def self.receipt(asset)
        data=asset.metadata.fetch("starter_cast")
        {asset_id:asset.id,name:asset.name,status:asset.status,phase:data["phase"],scene_id:data["scene_id"],project_id:data["project_id"],error:asset.error_message}
      end
      def self.status(access:,asset_id:nil)
        scope=StudioAsset.for_actor(access).where(site_id:access.site_id)
        asset=asset_id ? scope.find(asset_id) : scope.where(owner_id:access.user.id).where("metadata ->> 'starter_cast' IS NOT NULL").order(id: :desc).first
        return nil unless asset
        raise ArgumentError,"Not a starter scene" unless asset.metadata["starter_cast"]
        receipt(asset)
      end
    end
  end
end
