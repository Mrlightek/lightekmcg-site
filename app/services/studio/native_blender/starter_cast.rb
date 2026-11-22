# frozen_string_literal: true
module Studio
  module NativeBlender
    class StarterCast
      KEYS=%w[rain_v3 snow_v4].freeze
      QUEUE_GRACE=2.minutes
      def self.start(access:,payload:)
        if payload["retry_asset_id"].present?
          asset=StudioAsset.where(owner:access.user,site_id:access.site_id).find(payload["retry_asset_id"])
          asset.with_lock do
            raise ArgumentError,"Not a starter scene" unless asset.metadata["starter_cast"]
            requeue(asset) if asset.status=="failed" || delayed?(asset)
          end
          return receipt(asset)
        end
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A starter scene request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        name=payload.fetch("name","My first character scene").to_s.strip
        raise ArgumentError,"Name your scene (up to 120 characters)" unless name.length.between?(1,120)
        variant=normalize_variant(access,payload["character"])
        keys=variant ? [variant["rig"]].intersection(KEYS) : KEYS
        asset=nil
        access.user.with_lock do
          asset=StudioAsset.find_by(owner:access.user,request_key:key)
          if asset
            raise ArgumentError,"This request belongs to another starter scene" unless asset.site_id==access.site_id && asset.metadata.dig("starter_cast","name")==name && asset.metadata.dig("starter_cast","character")==variant
          else
            raise ArgumentError,"Wait for your current starter scene to finish" if StudioAsset.where(owner:access.user,site_id:access.site_id,status:%w[uploaded processing]).where("metadata ->> 'starter_cast' IS NOT NULL").exists?
            build={"name"=>name,"phase"=>"queued","character"=>variant}.compact
            source={"name"=>variant ? "Rigged Blender character" : "Rain and Snow starter cast",
              "credits"=>keys.map { |id| DemoCatalog.fetch(id).slice("name","credit","license","license_url","source_page") }}
            if variant&.key?("asset_id")
              original=source_asset!(access,variant.fetch("asset_id"))
              source["credits"]=original.metadata.dig("source","credits").presence || [original.metadata["source"]].compact
            end
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,name:name,kind:"blend",status:"uploaded",
              request_key:key,metadata:{"starter_cast"=>build,"source"=>source})
            StudioStarterCastJob.perform_later(asset.id)
          end
          if asset.status=="failed"
            asset.with_lock { requeue(asset) if asset.status=="failed" }
          end
        end
        receipt(asset)
      end
      def self.source_asset!(access,id)
        source=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"blend",status:"ready").find(id)
        unless source.native.attached? && !source.bundle.attached? && Array(source.metadata["missing_dependencies"]).empty?
          raise ArgumentError,"Choose a prepared, self-contained Blender file with a rig"
        end
        source
      end

      def self.normalize_variant(access,raw)
        return if raw.nil?
        raise ArgumentError,"Choose an available character rig" unless raw.is_a?(Hash) &&
          (raw.keys-%w[rig asset_id height facing tint]).empty? && (KEYS+["library"]).include?(raw["rig"])

        height=Float(raw.fetch("height",1),exception:false)
        facing=Integer(raw.fetch("facing",0).to_s,10,exception:false)
        tint=raw["tint"].presence
        unless height&.finite? && height.between?(0.75,1.25) && [-30,0,30].include?(facing) &&
            (!tint || (tint.is_a?(String) && tint.match?(/\A#[0-9a-fA-F]{6}\z/)))
          raise ArgumentError,"Choose a height from 75–125%, a facing angle and an optional hex palette tint"
        end
        variant={"rig"=>raw.fetch("rig"),"height"=>height,"facing"=>facing,"tint"=>tint&.downcase}.compact
        if variant["rig"]=="library"
          source=source_asset!(access,raw.fetch("asset_id"))
          scene=Array(source.metadata["scenes"]).find do |item|
            Array(item["objects"]).any? { |object| object.dig("definition","native_type")=="ARMATURE" }
          end
          raise ArgumentError,"This Blender asset has no rigged scene" unless scene
          variant.merge!("asset_id"=>source.id,"blob_id"=>source.native.blob.id,"scene"=>scene.fetch("name"))
        end
        variant
      end

      def self.delayed?(asset)
        asset.status=="uploaded" && asset.metadata.dig("starter_cast","phase")=="queued" &&
          asset.updated_at < QUEUE_GRACE.ago
      end

      def self.requeue(asset)
        asset.update!(status:"uploaded",error_message:nil,
          metadata:asset.metadata.merge("starter_cast"=>asset.metadata.fetch("starter_cast").merge("phase"=>"queued","queued_at"=>Time.current.iso8601(6))))
        StudioStarterCastJob.perform_later(asset.id)
      end

      def self.receipt(asset)
        data=asset.metadata.fetch("starter_cast")
        {asset_id:asset.id,name:asset.name,status:asset.status,phase:delayed?(asset) ? "delayed" : data["phase"],variant:data.key?("character"),scene_id:data["scene_id"],project_id:data["project_id"],error:asset.error_message}
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
