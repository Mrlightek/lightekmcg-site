# frozen_string_literal: true
require_relative "studio_ai_checks"
require_relative "studio_cpu_pool_checks"
require File.join(ROOT,"app/services/studio/workflows/scene_plan")
require File.join(ROOT,"app/services/studio/workflows/production")
require File.join(ROOT,"app/jobs/studio_comfy_workflow_job")
require File.join(ROOT,"app/services/nevaeh_os/specialist_context")
module Api; module Lightek; module Pwa; end; end; end
require File.join(ROOT,"app/controllers/api/lightek/pwa/studio_workflows_controller")
require "rack/mock"
Rails.application.routes.draw do
  post "/api/lightek/pwa/studio/workflows/:id/mcp",to:"api/lightek/pwa/studio_workflows#mcp"
end
class StudioComfyWorkflowTest < StudioAiTest
  StudioAiTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def workflow
    action("workflow_create",scene_id:@scene.id,prompt:"A sphere slides under bright lighting viewed from front",request_key:"comfy-workflow-123")
  end
  def with_ready
    runtime=Object.new
    runtime.define_singleton_method(:inventory) { {workflow:{ready:true}} }
    Studio::Ai::Runtime.stub(:new,runtime) { yield }
  end
  def rpc(operation,method,params={},token:Studio::Workflows::Production.token(operation),path_id:operation.id,origin:nil)
    env=Rack::MockRequest.env_for("/api/lightek/pwa/studio/workflows/#{path_id}/mcp",method:"POST",
      "CONTENT_TYPE"=>"application/json","HTTP_AUTHORIZATION"=>"Bearer #{token}","HTTP_ORIGIN"=>origin,
      input:JSON.generate({jsonrpc:"2.0",id:1,method:method,params:params}))
    status,headers,body=Rails.application.call(env)
    text=body.each.to_a.join;body.close if body.respond_to?(:close)
    [status,headers,text.empty? ? nil : JSON.parse(text)]
  end
  def test_prompt_planner_rejects_unsupported_or_executable_requests
    plan=Studio::Workflows::ScenePlan.parse("A cube spins under soft lighting viewed from front.")
    assert_equal "cube",plan["scene_preset"]
    assert_equal "spin",plan.dig("procedural_script_params","motion")
    assert_equal "workflow",NevaehOs::SpecialistContext.topic_for("studio.workspace.workflow.create",{})
    assert_match(/two-second 320×180/,NevaehOs::SpecialistContext.guidance("workflow"))
    ["A dragon flies over Atlanta","cube spins; rm -rf /","A cube spins and a sphere slides"].each do |prompt|
      assert_raises(ArgumentError) { Studio::Workflows::ScenePlan.parse(prompt) }
    end
  end
  def test_creation_is_scoped_idempotent_and_bounded
    with_ready do
      first=workflow
      assert_equal first,workflow
      operation=StudioOperation.find(first[:operation_id])
      assert_equal [320,180,24],operation.manifest.dig("scene","settings").values_at("resolution_x","resolution_y","frame_end")
      assert operation.metadata["draft_preview"]
      assert_raises(ArgumentError) { action("workflow_create",scene_id:@scene.id,prompt:"A cube spins",request_key:"comfy-workflow-123") }
      assert_raises(ActiveRecord::RecordNotFound) { action("workflow_create",user_id:@bob.id,scene_id:@scene.id,prompt:"A cube spins",request_key:"foreign-comfy") }
    end
  end
  def test_mcp_tokens_are_job_scoped_and_tools_cannot_accept_commands
    with_ready do
      operation=StudioOperation.find(workflow[:operation_id])
      assert_equal 200,rpc(operation,"initialize")[0]
      tools=rpc(operation,"tools/list")[2].dig("result","tools")
      assert_equal %w[studio_render studio_assemble studio_result],tools.map { |tool| tool["name"] }
      assert_equal 403,rpc(operation,"tools/list",{},token:"bad")[0]
      assert_equal 403,rpc(operation,"tools/list",{},path_id:operation.id+1)[0]
      assert_equal 403,rpc(operation,"tools/list",{},origin:"https://other.example.test")[0]
      response=rpc(operation,"tools/call",{name:"studio_render",arguments:{command:"rm -rf /"}})
      assert response[2].dig("result","isError")
      assert_nil operation.reload.metadata["workflow_render_id"]
      operation.update!(status:"cancelled")
      assert rpc(operation,"tools/call",{name:"studio_render",arguments:{}})[2].dig("result","isError")
    end
  end
  def test_expired_and_revoked_job_credentials_do_not_authorize_tools
    with_ready do
      operation=StudioOperation.find(workflow[:operation_id])
      token=Studio::Workflows::Production.token(operation)
      @alice.update!(role:"member");@site.update!(tenant:@bob);@project.update!(owner:@bob)
      assert_equal 403,rpc(operation,"tools/list",{},token:token)[0]
      operation.update!(created_at:2.hours.ago)
      assert_equal 403,rpc(operation,"tools/list")[0]
    end
  end
  def test_cancelling_a_workflow_cancels_its_pending_render_without_resubmitting
    with_ready do
      operation=StudioOperation.find(workflow[:operation_id])
      child_id=Studio::Workflows::Production.tool(operation,"studio_render",{})[:operation_id]
      assert_equal child_id,Studio::Workflows::Production.tool(operation,"studio_render",{})[:operation_id]
      operation.update!(status:"cancelled")
      StudioComfyWorkflowJob.perform_now(operation.id)
      assert_equal "cancelled",StudioOperation.find(child_id).status
      assert_equal "cancelled",operation.reload.status
    end
  end
  def test_real_comfyui_mcp_blender_ffmpeg_saved_video
    skip "Set STUDIO_COMFY_PROOF_URL to a running pinned ComfyUI with Lightek nodes" unless ENV["STUDIO_COMFY_PROOF_URL"]
    old_url=ENV["STUDIO_AI_URL"];old_root=ENV["BLENDER_OUTPUT_ROOT"]
    ENV["STUDIO_AI_URL"]=ENV.fetch("STUDIO_COMFY_PROOF_URL")
    output_root=Dir.mktmpdir("comfy-render-");ENV["BLENDER_OUTPUT_ROOT"]=output_root
    server=TCPServer.new("127.0.0.1",18466)
    origin="http://127.0.0.1:18466"
    result=workflow;operation=StudioOperation.find(result[:operation_id])
    original=Studio::Workflows::Production.method(:graph)
    graph=lambda do |row|
      value=original.call(row)
      context=JSON.parse(value.dig("1","inputs","context"))
      context["url"]="#{origin}/api/lightek/pwa/studio/workflows/#{row.id}/mcp"
      value["1"]["inputs"]["context"]=JSON.generate(context)
      value
    end
    Studio::Workflows::Production.stub(:graph,graph) { StudioComfyWorkflowJob.perform_now(operation.id) }
    assert_equal "running",operation.reload.status
    rendered=false;methods=[];deadline=Time.now+90
    while Time.now<deadline && !operation.reload.terminal?
      if IO.select([server],nil,nil,0.1)
        socket=server.accept;first=socket.gets;headers={}
        while (line=socket.gets) && line!="\r\n"
          key,value=line.split(":",2);headers[key.downcase]=value.strip
        end
        body=socket.read(headers.fetch("content-length","0").to_i)
        path=first.split(" ")[1];request=JSON.parse(body);methods<<request["method"]
        env=Rack::MockRequest.env_for(path,method:"POST","CONTENT_TYPE"=>"application/json",
          "HTTP_AUTHORIZATION"=>headers.fetch("authorization"),input:body)
        status,_,response=Rails.application.call(env)
        bytes=response.each.to_a.join;response.close if response.respond_to?(:close)
        socket.write("HTTP/1.1 #{status} OK\r\nContent-Type: application/json\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n#{bytes}");socket.close
      end
      child_id=operation.reload.metadata["workflow_render_id"]
      if child_id && !rendered
        Rails.stub(:root,Pathname(ROOT)) { ExecuteStudioOperationJob.perform_now(child_id) }
        rendered=true
        assert_equal "completed",StudioOperation.find(child_id).status
      end
      StudioComfyWorkflowJob.perform_now(operation.id)
    end
    assert_equal "completed",operation.reload.status,operation.error_message
    artifact=operation.artifacts.find_by!(kind:"video")
    artifact.file.blob.open do |file|
      metadata=JSON.parse(IO.popen(["ffprobe","-v","error","-show_streams","-show_format","-of","json",file.path],&:read))
      assert_in_delta 2,metadata.dig("format","duration").to_f,0.05
      video=metadata.fetch("streams").find { |stream| stream["codec_type"]=="video" }
      assert_equal [320,180],video.values_at("width","height")
      frames=IO.popen(["ffmpeg","-v","error","-i",file.path,"-f","framemd5","-"],&:read)
      hashes=frames.lines.reject { |line| line.start_with?("#") }.map { |line| line.split(",").last&.strip }
      assert_operator hashes.uniq.length,:>,1,"The output must contain actual animation"
      FileUtils.cp(file.path,ENV["STUDIO_COMFY_PROOF_VIDEO"]) if ENV["STUDIO_COMFY_PROOF_VIDEO"]
    end
    assert_includes methods,"initialize"
    assert_includes methods,"notifications/initialized"
    assert_includes methods,"tools/call"
    again=rpc(operation,"tools/call",{name:"studio_assemble",arguments:{}})
    assert_equal artifact.id,again[2].dig("result","structuredContent","artifact_id")
    assert_equal 1,operation.artifacts.where(kind:"video").count
    assert_raises(ArgumentError) { action("artifact_reuse",project_id:@project.id,artifact_id:artifact.id) }
  ensure
    server&.close
    ENV["STUDIO_AI_URL"]=old_url if defined?(old_url)
    ENV["BLENDER_OUTPUT_ROOT"]=old_root if defined?(old_root)
    FileUtils.rm_rf(output_root) if output_root
  end
end
