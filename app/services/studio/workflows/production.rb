# frozen_string_literal: true
require "json"
require "digest"
module Studio
  module Workflows
    class Production
      CAPABILITY="studio.workspace.workflow.create"
      TOOLS={"studio_render"=>"Queue or check this job's native 2D render", "studio_result"=>"Read this job's verified Studio artifact"}.freeze
      def self.scene!(access,id)
        scene=access.scene!(id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        scene
      end
      def self.plan(access:,payload:)
        scene!(access,payload.fetch("scene_id"))
        graph=ScenePlan.parse(payload.fetch("prompt"),seed:payload["seed"])
        {composition:graph,assets:Studio::Layered::Composition.catalog}
      end
      def self.save(access:,payload:)
        scene=scene!(access,payload.fetch("scene_id"))
        graph=Studio::Layered::Composition.normalize(payload.fetch("composition"))
        sources(access,graph)
        scene.with_lock do
          raise ArgumentError,"The scene changed. Refresh before saving its layers." unless scene.lock_version==Integer(payload.fetch("lock_version"))
          scene.update!(settings:scene.settings.merge("composition_2d"=>graph))
        end
        {composition:graph,lock_version:scene.lock_version}
      end
      def self.sources(access,graph)
        Studio::Layered::Composition.flatten(graph).map do |layer|
          if layer["template"]
            ["template:#{layer['template']}",Rails.root.join("public/lightek/assets2d",Studio::Layered::Composition::ASSETS.fetch(layer["template"]).last)]
          else
            asset=StudioAsset.for_actor(access).where(site_id:access.site_id,kind:"image",status:"ready").find(layer.fetch("asset_id"))
            raise ArgumentError,"Choose a published source image rather than a private preview" if asset.metadata["private_social_source"]
            blob=asset.proxy.attached? ? asset.proxy.blob : asset.file.blob
            raise ArgumentError,"Keep each source image under 25 MiB" if blob.byte_size>25.megabytes
            raise ArgumentError,"Use prepared PNG, JPEG, WebP, GIF or AVIF images" unless %w[image/png image/jpeg image/webp image/gif image/avif].include?(blob.content_type)
            blob.open do |file|
              head=file.read(16).to_s.b
              raster=head.start_with?("\x89PNG\r\n\x1a\n".b,"\xff\xd8\xff".b,"GIF87a","GIF89a") ||
                (head.start_with?("RIFF") && head[8,4]=="WEBP") || (head[4,4]=="ftyp" && %w[avif avis].include?(head[8,4]))
              raise ArgumentError,"This source is not a supported raster image" unless raster
            end
            ["asset:#{asset.id}",blob]
          end
        end.to_h
      end
      def self.preview(graph)
        output=graph.deep_dup;canvas=output.fetch("canvas")
        ratio=[1.0,640.0/[canvas["width"],canvas["height"]].max].min
        time=[2.0,canvas["duration"]].min/canvas["duration"]
        output["camera"]=output["camera"].transform_values { |value| value*time }
        canvas.merge!("width"=>((canvas["width"]*ratio/2).floor*2),"height"=>((canvas["height"]*ratio/2).floor*2),"fps"=>[canvas["fps"],12].min,"duration"=>[canvas["duration"],2].min)
        Studio::Layered::Composition.normalize(output)
      end
      def self.start(access:,payload:,final:false)
        scene=scene!(access,payload.fetch("scene_id"))
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Use a valid workflow request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        graph=if payload["composition"]
          Studio::Layered::Composition.normalize(payload["composition"])
        else
          ScenePlan.parse(payload.fetch("prompt"),seed:payload.fetch("seed",Digest::SHA256.hexdigest(key).first(8).to_i(16)))
        end
        source_map=sources(access,graph)
        bytes=source_map.values.sum { |source| source.is_a?(Pathname) ? source.size : source.byte_size }
        raise ArgumentError,"Keep total source images under 64 MiB for this composition" if bytes>64.megabytes
        operation=access.user.with_lock do
          scope=StudioOperation.where(capability:CAPABILITY,studio_project_id:access.projects.select(:id)).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'workflow_request_key' = ?",key).first
          if previous
            raise ArgumentError,"This request belongs to a different render" unless previous.studio_scene_id==scene.id && previous.metadata["scene_plan"]==graph && previous.metadata["draft_preview"]==!final
            next previous
          end
          raise ArgumentError,"Wait for your current scene render" if scope.where(status:%w[pending running]).exists? || scope.where("created_at > ?",1.minute.ago).count>=4
          rendered=final ? graph : preview(graph)
          op=scene.studio_operations.create!(studio_project:scene.studio_project,production:scene.production,
            operation_type:"edit_media",provider:"layered_2d",capability:CAPABILITY,status:final ? "awaiting_payment" : "pending",
            intent:{"user_id"=>access.user.id},manifest:{"composition_2d"=>rendered},metadata:{"draft_preview"=>!final,"layered_scene"=>true,
              "workflow_request_key"=>key,"scene_plan"=>graph,"workflow_nonce"=>SecureRandom.hex(24),"workflow_phase"=>"queued","cpu_routing_mode"=>"local"})
          blobs={}
          source_map.each_with_index do |(name,source),index|
            if source.is_a?(Pathname)
              op.layer_sources.attach(io:File.open(source),filename:"template-#{index}.svg",content_type:"image/svg+xml",identify:false)
              blob=op.layer_sources.blobs.last
            else
              op.layer_sources.attach(source);blob=source
            end
            blobs[name]=blob.id
          end
          op.update!(metadata:op.metadata.merge("layer_blobs"=>blobs))
          Studio::Billing::Quote.call(operation:op,rail: :stripe_card) if final
          op
        end
        enqueue(operation) unless final
        {operation_id:operation.id,status:operation.status,composition:graph,quote:operation.cost_quote.presence}.compact
      end
      def self.enqueue(operation)
        raise ArgumentError,"Checkout is required before final rendering" unless operation.metadata["draft_preview"] || operation.paid?
        ExecuteStudioOperationJob.perform_later(operation.id) if operation.status=="pending"
      end
      def self.verifier = Rails.application.message_verifier("studio-workflow-mcp-v1")
      def self.token(operation)
        verifier.generate({"id"=>operation.id,"nonce"=>operation.metadata.fetch("workflow_nonce")},expires_at:operation.created_at+1.hour)
      end
      def self.authorize!(id,token)
        proof=verifier.verified(token.to_s)
        raise ActiveRecord::RecordNotFound unless proof.is_a?(Hash) && proof["id"].to_s==id.to_s
        operation=StudioOperation.where(capability:CAPABILITY).find(id)
        raise ActiveRecord::RecordNotFound unless proof["nonce"]==operation.metadata["workflow_nonce"]
        access=Studio::PwaAccess.new("user_id"=>operation.intent.fetch("user_id"),"site_id"=>operation.studio_project.site_id)
        scene!(access,operation.studio_scene_id)
        LightekPwa::Policy.new(user:access.user,site:operation.studio_project.site).authorize!("studio")
        operation
      end
      def self.tool(operation,name,arguments)
        raise ArgumentError,"Unsupported workflow tool or arguments" unless TOOLS.key?(name) && arguments=={}
        raise ArgumentError,"This workflow is no longer active" if operation.status.in?(%w[failed cancelled]) || operation.created_at<1.hour.ago
        if name=="studio_render"
          enqueue(operation)
          {status:operation.reload.status,operation_id:operation.id}
        else
          result(operation)
        end
      end
      def self.result(operation)
        artifact=operation.artifacts.find_by(kind:"video")
        raise ArgumentError,"Rendering has not produced a saved video" unless operation.status=="completed" && artifact&.file&.attached?
        {status:"completed",operation_id:operation.id,artifact_id:artifact.id}
      end
    end
  end
end
