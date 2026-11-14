# frozen_string_literal: true
module Studio
  module Ai
    class Generation
      def self.start(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        prompt=payload.fetch("prompt").to_s.strip;negative=payload.fetch("negative","").to_s
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Describe your shot in 1–2000 characters" unless prompt.length.between?(1,2000) && negative.length<=2000
        raise ArgumentError,"Invalid generation request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        seed=Integer(payload.fetch("seed",Digest::SHA256.hexdigest(key).first(8).to_i(16)))
        raise ArgumentError,"Seed must be between 0 and 4294967295" unless seed.between?(0,2**32-1)
        recipe_id=payload.fetch("recipe").to_s;model=payload.fetch("model","").to_s
        intent={"scene_id"=>scene.id,"prompt"=>prompt,"negative"=>negative,"seed"=>seed,"recipe"=>recipe_id,"model"=>model}
        if payload["shot_id"].present?
          shot=Studio::Shots::Board.find(scene,payload["shot_id"])
          intent.merge!("shot_id"=>shot["id"],"shot_name"=>shot["name"])
        end
        asset=nil
        access.user.with_lock do
          asset=StudioAsset.find_by(owner:access.user,request_key:key)
          if asset
            raise ArgumentError,"This request key belongs to another generation" unless asset.site_id==access.site_id && asset.metadata["ai_intent"]==intent
            return receipt(asset)
          end
          runtime=Runtime.new;status=runtime.inventory
          recipe=status[:recipes].find{|r|r[:id]==recipe_id && r[:ready]}
          raise ArgumentError,status[:reason] || "This workflow is not ready on your local worker" unless recipe
          raise ArgumentError,"Choose an installed local model" unless model.empty? || status[:models].include?(model)
          _,graph=runtime.graph(recipe_id,prompt:prompt,negative:negative,seed:seed,model:model)
          raise ArgumentError,"Choose an installed local model" if graph.values.any?{|n|n["class_type"]=="CheckpointLoaderSimple" && n.dig("inputs","ckpt_name").blank?}
          pending=StudioAsset.where(owner:access.user,status:%w[uploaded processing]).where("metadata ->> 'ai_intent' IS NOT NULL").count
          raise ArgumentError,"Wait for your current generations to finish" if pending>=2
          asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,name:prompt.first(120),kind:recipe[:kind],status:"uploaded",request_key:key,metadata:{"ai_intent"=>intent,"ai_graph"=>graph,"ai_phase"=>"queued","ai_engine"=>"local_comfyui"})
          StudioAiGenerationJob.perform_later(asset.id)
        end
        receipt(asset)
      end
      def self.receipt(asset)
        {asset_id:asset.id,name:asset.name,kind:asset.kind,status:asset.status,phase:asset.metadata["ai_phase"],error:asset.error_message,prompt:asset.metadata.dig("ai_intent","prompt"),shot_id:asset.metadata.dig("ai_intent","shot_id"),shot_name:asset.metadata.dig("ai_intent","shot_name"),seed:asset.metadata.dig("ai_intent","seed"),preview_url:asset.proxy.attached? ? "/api/lightek/pwa/assets/#{asset.id}/proxy" : nil}
      end
      def self.list(access:,scene_id:)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        StudioAsset.for_actor(access).where(studio_project_id:scene.studio_project_id,site_id:access.site_id).where("metadata ->> 'ai_intent' IS NOT NULL").order(id: :desc).limit(30).map{|asset|receipt(asset)}
      end
    end
  end
end
