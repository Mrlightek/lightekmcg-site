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
        if payload["steps"].present?
          raise ArgumentError,"Choose 1–60 sampling steps" unless payload["steps"].to_s.match?(/\A(?:[1-9]|[1-5][0-9]|60)\z/)
          intent["steps"]=Integer(payload["steps"])
        end
        if payload["input_asset_id"].present?
          raise ArgumentError,"Choose a starting image ID" unless payload["input_asset_id"].to_s.match?(/\A[1-9]\d*\z/)
          intent["input_asset_id"]=Integer(payload["input_asset_id"])
        end
        if payload["shot_id"].present?
          shot=Studio::Shots::Board.find(scene,payload["shot_id"])
          intent.merge!("shot_id"=>shot["id"],"shot_name"=>shot["name"])
        end
        site=DymondSite::Site.find(access.site_id)
        asset=nil
        site.with_lock do
          access.user.with_lock do
            asset=StudioAsset.find_by(owner:access.user,request_key:key)
            if asset
              raise ArgumentError,"This request key belongs to another generation" unless asset.site_id==access.site_id && asset.metadata["ai_intent"]==intent
              return receipt(asset)
            end
            raise ArgumentError,"Wait for worker setup to finish before generating" if Setup.pending?(site)
            worker=site.manifest.to_h["studio_ai_worker"] || {"mode"=>"local"}
            runtime=Runtime.new(site:site,identity:worker);status=runtime.inventory
            recipe=status[:recipes].find{|r|r[:id]==recipe_id && r[:ready]}
            raise ArgumentError,status[:reason] || "This workflow is not ready on your local worker" unless recipe
            raise ArgumentError,"Choose an installed local model" unless model.empty? || status[:models].include?(model)
            source=nil
            if recipe[:input_kind]=="image"
              raise ArgumentError,"Choose a prepared starting image" unless intent["input_asset_id"]
              source=StudioAsset.for_actor(access).where(site_id:access.site_id).find(intent["input_asset_id"])
              InputImage.validate!(source)
            elsif intent["input_asset_id"]
              raise ArgumentError,"This workflow does not accept a starting image"
            end
            _,graph=runtime.graph(recipe_id,prompt:prompt,negative:negative,seed:seed,model:model,steps:intent["steps"])
            raise ArgumentError,"Choose an installed local model" if graph.values.any?{|n|n["class_type"]=="CheckpointLoaderSimple" && n.dig("inputs","ckpt_name").blank?}
            pending=StudioAsset.where(owner:access.user,status:%w[uploaded processing]).where("metadata ->> 'ai_intent' IS NOT NULL").count
            raise ArgumentError,"Wait for your current generations to finish" if pending>=2
            asset=StudioAsset.create!(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,name:prompt.first(120),kind:recipe[:kind],status:"uploaded",request_key:key,metadata:{"ai_intent"=>intent,"ai_graph"=>graph,"ai_phase"=>"queued","ai_engine"=>"self_hosted_comfyui","ai_worker"=>worker})
            if source
              blob=source.proxy.blob
              asset.ai_input.attach(blob)
              asset.update!(metadata:asset.metadata.merge("ai_input_source"=>{"asset_id"=>source.id,"blob_id"=>blob.id,"checksum"=>blob.checksum}))
            end
            StudioAiGenerationJob.perform_later(asset.id)
          end
        end
        receipt(asset)
      end
      def self.receipt(asset)
        {asset_id:asset.id,name:asset.name,kind:asset.kind,status:asset.status,recipe:asset.metadata.dig("ai_intent","recipe"),steps:asset.metadata.dig("ai_intent","steps") || asset.metadata.fetch("ai_graph",{}).values.find { |node| node["class_type"]=="KSampler" }&.dig("inputs","steps"),phase:asset.metadata["ai_phase"],input_asset_id:asset.metadata.dig("ai_intent","input_asset_id"),driver_asset_id:asset.metadata.dig("ai_intent","driver_asset_id"),input_url:asset.ai_input.attached? ? "/dashboard/studio-broadcasting/assets/#{asset.id}/input?site_id=#{asset.site_id}" : nil,error:asset.error_message,prompt:asset.metadata.dig("ai_intent","prompt"),shot_id:asset.metadata.dig("ai_intent","shot_id"),shot_name:asset.metadata.dig("ai_intent","shot_name"),seed:asset.metadata.dig("ai_intent","seed"),preview_url:asset.proxy.attached? ? "/api/lightek/pwa/assets/#{asset.id}/proxy" : nil}
      end
      def self.list(access:,scene_id:)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        StudioAsset.for_actor(access).where(studio_project_id:scene.studio_project_id,site_id:access.site_id).where("metadata ->> 'ai_intent' IS NOT NULL").order(id: :desc).limit(30).map{|asset|receipt(asset)}
      end
    end
  end
end
