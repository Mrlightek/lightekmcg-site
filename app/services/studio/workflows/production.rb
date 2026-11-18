# frozen_string_literal: true
require "json"
module Studio
  module Workflows
    class Production
      CAPABILITY="studio.workspace.workflow.create"
      NODES=%w[LightekStudioJob LightekBlenderRender LightekFFmpegAssembly LightekStudioResult].freeze
      TOOLS={"studio_render"=>"Queue or check this job's bounded Blender render",
        "studio_assemble"=>"Assemble this job's rendered video with FFmpeg",
        "studio_result"=>"Read this job's verified Studio artifact"}.freeze
      def self.start(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        plan=ScenePlan.parse(payload.fetch("prompt"))
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Use a valid workflow request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        site=scene.studio_project.site
        operation=access.user.with_lock do
          scope=StudioOperation.where(capability:CAPABILITY,studio_project_id:access.projects.select(:id))
            .where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'workflow_request_key' = ?",key).first
          if previous
            raise ArgumentError,"This request belongs to a different workflow" unless previous.studio_scene_id==scene.id && previous.metadata["scene_plan"]==plan
            next previous
          end
          raise ArgumentError,"Wait for your current workflow draft" if scope.where(status:%w[pending running]).where("created_at > ?",1.hour.ago).exists? || scope.where("created_at > ?",1.minute.ago).count>=4
          identity=site.manifest.to_h["studio_ai_worker"] || {"mode"=>"local"}
          runtime=Studio::Ai::Runtime.new(site:site,identity:identity)
          status=runtime.inventory
          raise ArgumentError,status[:reason] || "Install the Lightek ComfyUI workflow nodes first" unless status.dig(:workflow,:ready)
          manifest=Studio::Compute::ProceduralMovie.build(scene,plan.fetch("scene_preset"),plan.fetch("procedural_script_params"),draft:true)
          scene.studio_operations.create!(studio_project:scene.studio_project,production:scene.production,
            operation_type:"build_scene",provider:"comfyui",capability:CAPABILITY,status:"pending",manifest:manifest,
            intent:{"user_id"=>access.user.id},metadata:{"draft_preview"=>true,"comfy_workflow"=>true,
              "workflow_request_key"=>key,"scene_plan"=>plan,"prompt"=>payload.fetch("prompt").to_s.strip,
              "workflow_nonce"=>SecureRandom.hex(24),"workflow_worker"=>identity,"workflow_phase"=>"queued"})
        end
        StudioComfyWorkflowJob.perform_later(operation.id) if operation.status=="pending"
        {operation_id:operation.id,status:operation.status}
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
        access.scene!(operation.studio_scene_id)
        LightekPwa::Policy.new(user:access.user,site:operation.studio_project.site).authorize!("studio")
        operation
      end
      def self.graph(operation)
        site=operation.studio_project.site
        origin="https://#{site.host}"
        context={url:"#{origin}/api/lightek/pwa/studio/workflows/#{operation.id}/mcp",token:token(operation)}
        {"1"=>{"class_type"=>NODES[0],"inputs"=>{"context"=>JSON.generate(context)}},
         "2"=>{"class_type"=>NODES[1],"inputs"=>{"job"=>["1",0]}},
         "3"=>{"class_type"=>NODES[2],"inputs"=>{"job"=>["2",0]}},
         "4"=>{"class_type"=>NODES[3],"inputs"=>{"job"=>["3",0]}}}
      end
      def self.tool(operation,name,arguments)
        raise ArgumentError,"Unsupported workflow tool or arguments" unless TOOLS.key?(name) && arguments=={}
        raise ArgumentError,"This workflow is no longer active" if operation.status.in?(%w[failed cancelled]) || operation.created_at<1.hour.ago
        case name
        when "studio_render" then render(operation)
        when "studio_assemble" then assemble(operation)
        when "studio_result" then result(operation)
        end
      end
      def self.render(operation)
        child=nil
        operation.with_lock do
          raise ArgumentError,"This workflow is no longer active" if operation.status.in?(%w[failed cancelled])
          child=operation.studio_project.studio_operations.find_by(id:operation.metadata["workflow_render_id"])
          unless child
            pools=Studio::Compute::ProceduralMovie.pools(operation.studio_project.site)
            route=pools.include?("remote") ? "remote" : pools.first
            raise ArgumentError,"No CPU render route is available" unless route
            child=operation.studio_scene.studio_operations.create!(studio_project:operation.studio_project,
              production:operation.production,operation_type:"build_scene",provider:"blender",
              capability:"studio.workspace.blender.preview",status:"pending",intent:operation.intent,
              manifest:operation.manifest,metadata:{"draft_preview"=>true,"workflow_parent_id"=>operation.id,"cpu_routing_mode"=>route})
            operation.update!(metadata:operation.metadata.merge("workflow_render_id"=>child.id,"workflow_phase"=>"rendering"))
            ExecuteStudioOperationJob.perform_later(child.id)
          end
        end
        raise ArgumentError,"The Blender worker could not finish this draft" if child.status.in?(%w[failed cancelled])
        {status:child.status,operation_id:child.id}
      end
      def self.assemble(operation)
        operation.with_lock do
          raise ArgumentError,"This workflow is no longer active" if operation.status.in?(%w[failed cancelled])
          return result(operation) if operation.metadata["workflow_artifact_id"]
          child=operation.studio_project.studio_operations.find(operation.metadata.fetch("workflow_render_id"))
          raise ArgumentError,"Render this workflow's scene first" unless child.status=="completed" && child.metadata["workflow_parent_id"]==operation.id
          source=child.artifacts.find_by!(kind:"video")
          raise ArgumentError,"The render has no saved video" unless source.file.attached?
          operation.update!(metadata:operation.metadata.merge("workflow_phase"=>"assembling"))
          Studio::MediaProcess.temporary_directory("comfy-assembly-") do |root|
            input=File.join(root,"source.mp4");output=File.join(root,"workflow-draft.mp4")
            source.file.blob.open { |file| FileUtils.cp(file.path,input) }
            command=["ffmpeg","-v","error","-y","-protocol_whitelist","file,pipe","-i",input,"-map","0:v:0","-an","-c:v","copy","-movflags","+faststart",output]
            if Rails.env.production?
              command=Studio::MediaProcess.container(command.map { |part| part.sub(root,"/work") },root:root,
                image:Studio::NativeBlender::Runtime.image(:media),memory:"512m")
            end
            Studio::MediaProcess.run!(command,timeout:30)
            artifact=operation.artifacts.create!(kind:"video",filename:"workflow-draft.mp4")
            artifact.file.attach(io:File.open(output),filename:"workflow-draft.mp4",content_type:"video/mp4")
            operation.update!(metadata:operation.metadata.merge("workflow_artifact_id"=>artifact.id,"workflow_phase"=>"assembled"))
          end
          result(operation)
        end
      end
      def self.result(operation)
        artifact=operation.artifacts.find_by(id:operation.metadata["workflow_artifact_id"],kind:"video")
        raise ArgumentError,"Assembly has not produced a saved video" unless artifact&.file&.attached?
        {status:"completed",operation_id:operation.id,artifact_id:artifact.id}
      end
      def self.cancel_child(operation)
        child=operation.studio_project.studio_operations.find_by(id:operation.metadata["workflow_render_id"])
        return unless child && child.metadata["workflow_parent_id"]==operation.id
        child.with_lock do
          child.update!(status:"cancelled",completed_at:Time.current,error_message:"The parent workflow is no longer active.") unless child.terminal?
        end
      end
    end
  end
end
